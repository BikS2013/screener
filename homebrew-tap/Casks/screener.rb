cask "screener" do
  version "0.1.0,1"
  sha256 "b228d30dfbf8c1223afd3502f2154c4ecd5729cc33cb3ecbaa9bf596a6ef6e53"

  url "https://github.com/BikS2013/screener/releases/download/v#{version.csv.first}-b#{version.csv.second}/screener-#{version.csv.first}.dmg"
  name "screener"
  desc "Select any screen area and copy its text (English and Greek OCR)"
  homepage "https://github.com/BikS2013/screener"

  livecheck do
    url :url
    regex(/^v?(\d+(?:\.\d+)+)-b(\d+)$/i)
    strategy :github_latest do |json, regex|
      match = json["tag_name"]&.match(regex)
      next if match.blank?

      "#{match[1]},#{match[2]}"
    end
  end

  depends_on arch: :arm64
  depends_on macos: :sonoma
  depends_on formula: "tesseract"

  app "screener.app"

  uninstall quit: "com.local.screener"

  zap trash: "~/.tool-agents/screener"

  caveats <<~EOS
    First launch:
      1. Open screener (menu-bar app, no Dock icon) and click
         "Create Config from Example". It writes ~/.tool-agents/screener/config.json
         and installs the Greek and English OCR data next to it.
      2. Press Ctrl-Option-Cmd-T and allow Screen Recording when macOS asks
         (System Settings > Privacy & Security > Screen & System Audio Recording),
         then quit and reopen screener.

    ~/.tool-agents/screener is kept on uninstall and removed on zap.
  EOS
end
