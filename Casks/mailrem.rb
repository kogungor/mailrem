cask "mailrem" do
  version "2.0.0"
  sha256 "b9b113a72cb855ba31c51bfed128b8e3297de171a2d9abc1400b80021da69af8"

  url "https://github.com/kogungor/mailrem/releases/download/v#{version}/MailRem-#{version}.dmg"
  name "MailRem"
  desc "Send the selected Apple Mail message to a Reminders list"
  homepage "https://github.com/kogungor/mailrem"

  depends_on macos: ">= :ventura"

  app "MailRem.app"

  uninstall quit: "com.kogungor.mailrem"

  zap trash: "~/Library/Preferences/com.kogungor.mailrem.plist"
end
