cask "mailrem" do
  version "2.2.0"
  sha256 "4e25b716f43061bddd25ad22ebe4e776c6a1ed8289632225c9157045f004efab"

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
