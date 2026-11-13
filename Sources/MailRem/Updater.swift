import AppKit
import Foundation
import Security

struct AvailableUpdate {
    let version: String
    let downloadURL: URL
}

enum UpdateError: Error {
    case badResponse
    case mountFailed
    case appNotFound
    case badSignature
    case unsignedBuild
    case notWritable
}

/// Checks GitHub for a newer release and installs it in place.
///
/// An update is only installed when the downloaded app is signed with the same
/// Developer ID team as the running app.
final class Updater {
    static let latestReleaseAPI = URL(string: "https://api.github.com/repos/kogungor/mailrem/releases/latest")!
    static let latestReleasePage = URL(string: "https://github.com/kogungor/mailrem/releases/latest")!
    private static let bundleIdentifier = "com.kogungor.mailrem"
    private static let checkInterval: TimeInterval = 6 * 60 * 60

    private(set) var available: AvailableUpdate?
    private(set) var isInstalling = false

    /// Called on the main thread whenever `available` or `isInstalling` changes.
    var onChange: (() -> Void)?
    /// Called on the main thread when an installation fails.
    var onInstallFailure: ((Error) -> Void)?

    private var timer: Timer?

    var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    // MARK: - Checking

    func startAutomaticChecks() {
        timer?.invalidate()
        timer = nil
        guard Settings.automaticUpdateChecks else { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in self?.automaticCheck() }
        timer = Timer.scheduledTimer(withTimeInterval: Self.checkInterval, repeats: true) { [weak self] _ in
            self?.automaticCheck()
        }
    }

    private func automaticCheck() {
        guard Settings.automaticUpdateChecks else { return }
        check { [weak self] result in
            if case .success(.some) = result, Settings.autoInstallUpdates {
                self?.install()
            }
        }
    }

    /// Asks GitHub for the latest release. The completion runs on the main thread
    /// with the update, or nil when the app is up to date.
    func check(completion: ((Result<AvailableUpdate?, Error>) -> Void)? = nil) {
        var request = URLRequest(url: Self.latestReleaseAPI)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("MailRem/\(currentVersion)", forHTTPHeaderField: "User-Agent")

        let current = currentVersion
        URLSession.shared.dataTask(with: request) { [weak self] data, _, error in
            let result = Result<AvailableUpdate?, Error> {
                if let error = error { throw error }
                guard let data = data else { throw UpdateError.badResponse }
                return try Self.parseRelease(data, currentVersion: current)
            }
            DispatchQueue.main.async {
                guard let self = self else { return }
                switch result {
                case .success(let update):
                    log.notice("Update check: current \(current, privacy: .public), available \(update?.version ?? "none", privacy: .public)")
                    self.available = update
                    self.onChange?()
                case .failure(let error):
                    log.error("Update check failed: \(String(describing: error), privacy: .public)")
                }
                completion?(result)
            }
        }.resume()
    }

    private static func parseRelease(_ data: Data, currentVersion: String) throws -> AvailableUpdate? {
        guard let release = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = release["tag_name"] as? String,
              let assets = release["assets"] as? [[String: Any]] else {
            throw UpdateError.badResponse
        }
        let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        guard version.compare(currentVersion, options: .numeric) == .orderedDescending else { return nil }

        for asset in assets {
            guard let name = asset["name"] as? String, name.hasSuffix(".dmg"),
                  let urlString = asset["browser_download_url"] as? String,
                  let url = URL(string: urlString),
                  url.scheme == "https", url.host == "github.com" else { continue }
            return AvailableUpdate(version: version, downloadURL: url)
        }
        return nil
    }

    // MARK: - Installing

    /// Downloads the available update, replaces this app with it and relaunches.
    func install() {
        guard let update = available, !isInstalling else { return }
        isInstalling = true
        onChange?()
        log.notice("Installing update \(update.version, privacy: .public)")

        URLSession.shared.downloadTask(with: update.downloadURL) { [weak self] location, _, error in
            guard let self = self else { return }
            do {
                guard let location = location else { throw error ?? UpdateError.badResponse }
                let diskImage = FileManager.default.temporaryDirectory
                    .appendingPathComponent("MailRem-update-\(UUID().uuidString).dmg")
                try FileManager.default.moveItem(at: location, to: diskImage)
                defer { try? FileManager.default.removeItem(at: diskImage) }

                try self.replaceApp(fromDiskImage: diskImage)
                log.notice("Update installed, relaunching")
                DispatchQueue.main.async { self.relaunch() }
            } catch {
                log.error("Update failed: \(String(describing: error), privacy: .public)")
                DispatchQueue.main.async {
                    self.isInstalling = false
                    self.onChange?()
                    self.onInstallFailure?(error)
                }
            }
        }.resume()
    }

    private func replaceApp(fromDiskImage diskImage: URL) throws {
        let fileManager = FileManager.default
        let target = Bundle.main.bundleURL
        let parent = target.deletingLastPathComponent()

        // An app opened straight from a download runs from a read-only,
        // randomized location and cannot replace itself.
        guard !target.path.contains("/AppTranslocation/"),
              fileManager.isWritableFile(atPath: parent.path),
              fileManager.isWritableFile(atPath: target.path) else {
            throw UpdateError.notWritable
        }

        let mountPoint = fileManager.temporaryDirectory
            .appendingPathComponent("MailRem-mount-\(UUID().uuidString)")
        try fileManager.createDirectory(at: mountPoint, withIntermediateDirectories: true)
        guard Self.run("/usr/bin/hdiutil", ["attach", diskImage.path, "-nobrowse", "-readonly",
                                            "-noautoopen", "-mountpoint", mountPoint.path]) == 0 else {
            throw UpdateError.mountFailed
        }
        defer {
            Self.run("/usr/bin/hdiutil", ["detach", mountPoint.path, "-force"])
            try? fileManager.removeItem(at: mountPoint)
        }

        let source = mountPoint.appendingPathComponent(target.lastPathComponent)
        guard fileManager.fileExists(atPath: source.path) else { throw UpdateError.appNotFound }
        try Self.verifySignature(of: source)

        let staged = parent.appendingPathComponent(".MailRem-update-\(UUID().uuidString).app")
        try fileManager.copyItem(at: source, to: staged)
        do {
            try Self.verifySignature(of: staged)
            _ = try fileManager.replaceItemAt(target, withItemAt: staged)
        } catch {
            try? fileManager.removeItem(at: staged)
            throw error
        }
    }

    private func relaunch() {
        // Wait for this process to exit, then open the replaced app.
        let script = "while /bin/kill -0 \(ProcessInfo.processInfo.processIdentifier) 2>/dev/null; do /bin/sleep 0.2; done; /usr/bin/open \"$0\""
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", script, Bundle.main.bundlePath]
        try? process.run()
        NSApp.terminate(nil)
    }

    @discardableResult
    private static func run(_ tool: String, _ arguments: [String]) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return -1
        }
        process.waitUntilExit()
        return process.terminationStatus
    }

    // MARK: - Signature

    /// Throws unless the app at `url` is a valid MailRem build signed with a
    /// Developer ID certificate from the same team as the running app.
    private static func verifySignature(of url: URL) throws {
        let teamID = try runningTeamIdentifier()
        let requirementText = """
        anchor apple generic and identifier "\(bundleIdentifier)" \
        and certificate 1[field.1.2.840.113635.100.6.2.6] exists \
        and certificate leaf[field.1.2.840.113635.100.6.1.13] exists \
        and certificate leaf[subject.OU] = "\(teamID)"
        """

        var requirement: SecRequirement?
        guard SecRequirementCreateWithString(requirementText as CFString, [], &requirement) == errSecSuccess,
              let requirement = requirement else {
            throw UpdateError.badSignature
        }
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess, let code = code else {
            throw UpdateError.badSignature
        }
        let flags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSStrictValidate | kSecCSCheckNestedCode)
        guard SecStaticCodeCheckValidity(code, flags, requirement) == errSecSuccess else {
            throw UpdateError.badSignature
        }
    }

    /// The Developer ID team that signed the running app. Ad-hoc builds have none
    /// and therefore never update themselves.
    private static func runningTeamIdentifier() throws -> String {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code = code else {
            throw UpdateError.unsignedBuild
        }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode = staticCode else {
            throw UpdateError.unsignedBuild
        }
        var information: CFDictionary?
        guard SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation),
                                            &information) == errSecSuccess,
              let dictionary = information as? [String: Any],
              let teamID = dictionary[kSecCodeInfoTeamIdentifier as String] as? String,
              !teamID.isEmpty else {
            throw UpdateError.unsignedBuild
        }
        return teamID
    }
}
