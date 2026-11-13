cask "mailrem" do
  version "2.3.0"
  sha256 "cc2fb46747901b1fed6d9cb1e55b916dacd967c4c5ffbc1981243e3e7e6d7295"

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
