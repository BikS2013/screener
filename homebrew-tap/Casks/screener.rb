cask "screener" do
  version "0.2.1"
  sha256 "0475eea3b053650a373d254eca1c91400112f7d383a61eb1937fb20a5519d4fb"

  url "https://github.com/biks2013-tools/screener/releases/download/v#{version}/screener-#{version}.zip"
  name "screener"
  desc "Menu bar app that copies the text of any screen area (English and Greek OCR)"
  homepage "https://github.com/biks2013-tools/screener"

  depends_on arch: :arm64
  depends_on formula: "tesseract"
  depends_on macos: :sonoma

  app "screener.app"

  postflight_steps do
    run "/usr/bin/osascript",
        args: [
          "-e",
          'display notification "Menu bar icon > Create Config from Example." with title "screener installed"',
        ]
  end

  uninstall quit: "com.local.screener"

  zap trash: "~/.tool-agents/screener"

  caveats <<~EOS
    First launch: open screener (menu bar icon, no Dock icon) and click
    "Create Config from Example". It writes ~/.tool-agents/screener/config.json
    and installs the Greek and English OCR data next to it.

    screener requires Screen Recording permission to read the screen:
      System Settings > Privacy & Security > Screen & System Audio Recording > enable screener
      (macOS asks on the first capture; quit and reopen screener afterwards)

    To start screener at login:
      menu bar icon > Launch at Login

    Global hotkeys (configurable in Settings, from the menu bar icon):
      Ctrl+Option+Cmd+T  — select an area on any screen and copy its text
      Ctrl+Option+Cmd+H  — recent captures

    Inside the selection overlay:
      Drag / Arrows      — select (Shift = faster, Option = fine; Space anchors, Return captures)
      T                  — text mode: arrows jump between text lines, Shift+arrows extend
      F                  — preserve the screen format / plain sequential text
      Tab                — next screen
      Esc                — cancel
  EOS
end
