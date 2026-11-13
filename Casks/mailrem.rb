cask "mailrem" do
  version "2.1.0"
  sha256 "ffcc4f2d92ba033f7945149a0ce784afe57e5727a9b29eb8915d27163b7cb1ba"

  url "https://github.com/kogungor/mailrem/releases/download/v#{version}/MailRem-#{version}.dmg"
  name "MailRem"
  desc "Send the selected Apple Mail message to a Reminders list"
  homepage "https://github.com/kogungor/mailrem"

  auto_updates true
  depends_on macos: ">= :ventura"

  app "MailRem.app"

  uninstall quit: "com.kogungor.mailrem"

  zap trash: "~/Library/Preferences/com.kogungor.mailrem.plist"
end
