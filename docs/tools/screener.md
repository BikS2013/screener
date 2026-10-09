<screener>
    <objective>
        Native macOS menu-bar app (Swift, AppKit + ScreenCaptureKit + Apple Vision + Tesseract CLI).
        A configurable global hotkey shows an almost-transparent overlay on every connected screen;
        the user drags a rectangle anywhere, the region is captured and OCR'd (English + Greek,
        auto-detected: Vision for Latin text, Tesseract ell+eng when Greek is present) and the
        recognised text (in the on-screen layout or as plain sequential text, switchable in the overlay)
        is copied to the clipboard, with a toast, a sound,
        and an in-memory capture history in the menu-bar menu. A Settings window edits the config file.
    </objective>
    <command>
        open -a screener          (installed at /Applications/screener.app, bundle id com.local.screener)

        Headless modes of the same binary (for scripting / verification):
          /Applications/screener.app/Contents/MacOS/screener --check-config
          /Applications/screener.app/Contents/MacOS/screener --ocr-file <image.png>
    </command>
    <info>
        <description>
            Screener runs as a macOS menu-bar (status-item) app with no Dock icon (LSUIElement).
            It registers global hotkeys via Carbon RegisterEventHotKey (no Accessibility permission
            needed). On activation it draws a borderless, almost-transparent window on every
            connected NSScreen (level .screenSaver, joins all Spaces and full-screen apps); the user
            drags a selection rectangle on any screen. On mouse-up the region is captured with
            ScreenCaptureKit (SCScreenshotManager, native pixel resolution, Screener's own windows
            excluded), then OCR'd:
              - "vision"    -> Apple Vision (VNRecognizeTextRequest, accurate) with ocr.visionLanguages.
              - "tesseract" -> the Tesseract CLI at ocr.tesseractPath with -l ocr.tesseractLanguages,
                               --psm ocr.tesseractPageSegMode and --tessdata-dir ocr.tessdataDir. The
                               image is converted to grayscale, inverted when dark (dark mode),
                               upscaled 2x on 1x displays and padded before being piped to stdin.
              - "auto"      -> runs both engines in parallel; if Tesseract's output contains Greek
                               characters it wins, otherwise Vision's result is used (Vision is the
                               stronger engine for Latin script but cannot read Greek at all).
            Both engines report word boxes (Vision per-word boxes; Tesseract TSV output), which are
            grouped into visual rows (top -> bottom, left -> right) and rendered in one of two formats,
            chosen per capture with the overlay's format switch (keyboard.toggleFormat, or a click on the
            switch at the bottom of the active screen; it starts at output.preserveFormat every time):
              - preserved: the on-screen layout — line breaks, indentation and table columns aligned on
                a character grid (median character width; a gap wider than 2.5 characters counts as a
                column gap, ordinary word spacing stays one space), and a blank line for a vertical gap
                taller than a line.
              - plain: one sequential text — rows joined with single spaces, a word hyphenated across
                a line end re-joined ("li-" + "ne" -> "line"), whitespace collapsed.
            The toast names the format that was used.
            With output.greekMonotonic, stray polytonic marks emitted by the Tesseract Greek model
            ("εἶναι") are converted to monotonic ("είναι"). With output.greekCorrection, Tesseract's
            Greek look-alike mistakes are repaired, every whole-word change confirmed by the macOS Greek
            spelling dictionary: µ (MICRO SIGN) → μ; Latin letters inside Greek words; whole words read
            in the wrong script inside Greek sentences ("Eva" → "ένα", "kat" → "και") while genuine
            Latin words stay ("IBM", "OK", "iPhone", "info@nbg.gr"); missing/spurious accents
            ("ενα" → "ένα", "Ό" → "Ο"); letters read as digits ("ΑΒΓ-Ί23" → "ΑΒΓ-123").

            Keyboard selection inside the overlay (all keys configurable, keyboard.*):
              - free mode: arrows move a crosshair (the real pointer follows) by keyboard.defaultStepPoints;
                with keyboard.fasterModifier by keyboard.fasterStepPoints, with keyboard.fineModifier by
                keyboard.fineStepPoints; keyboard.anchor drops/clears an
                anchor and the arrows then stretch the rectangle; keyboard.confirm captures it.
              - text mode (keyboard.toggleTextMode, or keyboard.startInTextMode): the screen's text lines
                are detected (Vision fast level, boxes only) and outlined; arrows jump to the nearest
                line in that direction, keyboard.extendModifier+arrows (or keyboard.anchor) extends the
                selection over several lines (every line between the two ends is included at its full
                width; a separate column beside them is not), a mouse click focuses a line; keyboard.confirm captures.
              - keyboard.nextScreen moves the keyboard focus to the next display; hotkeys.cancel exits.
              - keyboard.toggleFormat flips the format switch (preserved / plain) at any time, also
                while dragging, so the choice applies to the capture about to be made.
            The mouse keeps working in both modes (drag to select).
            Warm-up: Apple Vision's accurate recogniser needs ~20 s the first time the system loads its
            model (a system-wide cost that returns after macOS evicts the model). Screener runs the
            full pipeline on a tiny sample in the background whenever the configuration loads (at
            launch and on reload), and re-warms Vision each time the overlay opens, so real captures
            don't pay that delay. Timings are logged (subsystem com.local.screener,
            category warmup).
            The text is written to NSPasteboard. Success shows a toast (feedback.toast /
            feedback.toastDurationSeconds) and plays feedback.soundName (feedback.sound). Failures
            (capture error, no text found) always show a toast, even when toasts are disabled.
            The last history.size captures are kept in memory only (never written to disk) and are
            listed in the menu-bar menu; clicking one copies it again.
            The menu also offers: Settings…, Reload Config, Open Config Folder, Launch at Login,
            and — only when config.json is missing — Create Config from Example.
        </description>

        <macos_permissions>
            Screen Recording permission is REQUIRED (System Settings -> Privacy & Security ->
            Screen & System Audio Recording -> enable Screener). On the first capture attempt without
            it, Screener triggers the system prompt and shows an alert; after granting, quit and
            reopen Screener. The permission is bound to the code signature, so build with a stable
            SCREENER_SIGN_IDENTITY to keep it across rebuilds (ad-hoc "-" signing loses it).
        </macos_permissions>

        <prerequisites>
            - Tesseract CLI (for the "tesseract" and "auto" engines):  brew install tesseract
            - Tesseract trained data in ocr.tessdataDir: bundled in the app and installed by
              "Create Config from Example"; for development: scripts/install-tessdata.sh ell eng
              (tessdata_best models pinned by SHA-256 in packaging/macos/tessdata.lock)
            - Build: Xcode / Swift 6 toolchain, macOS 14 or later.
        </prerequisites>

        <configuration>
            Screener has NO environment-variable configuration. All runtime configuration lives in a
            single required JSON file:

                ~/.tool-agents/screener/config.json   (mode 0600)

            It is created only on explicit user action from config.example.json: the first-launch
            prompt or the menu item "Create Config from Example" (shown only while the file is missing),
            which also copies the Tesseract models bundled in the app (Contents/Resources/tessdata) to
            ~/.tool-agents/screener/tessdata without overwriting existing files; or, in development,
            scripts/install-config.sh + scripts/install-tessdata.sh. Thereafter the file is edited by
            hand or by the Settings window.
            Screener creates ~/.tool-agents/screener/ (0700) on startup if it is missing.

            No-fallback rule: every key below is REQUIRED. A missing key, wrong type, or failed
            validation produces a visible alert naming the key (e.g. "missing required key
            'ocr.engine'"), the menu-bar icon turns into a warning triangle, and hotkeys stay
            unregistered until the file is fixed and reloaded. No built-in default is ever used.

            Keys (dot-path = nested JSON object path):

            | Key                           | Type          | Validation / purpose                                                        |
            |-------------------------------|---------------|-----------------------------------------------------------------------------|
            | hotkeys.activate              | string        | Global hotkey that shows the overlay, e.g. "ctrl+option+cmd+t"; needs cmd/ctrl/option or an F-key |
            | hotkeys.cancel                | string        | Key that dismisses the overlay, e.g. "escape" (right-click also cancels)    |
            | hotkeys.showHistory           | string        | Global hotkey that opens the menu-bar menu, e.g. "ctrl+option+cmd+h"; must differ from activate |
            | ocr.engine                    | string enum   | "auto" \| "vision" \| "tesseract"                                            |
            | ocr.visionLanguages           | string[]      | Vision language codes, e.g. ["en-US"]; each must be supported by Vision     |
            | ocr.tesseractLanguages        | string        | Tesseract -l string, e.g. "ell+eng"; each needs <lang>.traineddata          |
            | ocr.tesseractPath             | string (path) | Tesseract executable, e.g. /opt/homebrew/bin/tesseract (~ is expanded)       |
            | ocr.tessdataDir               | string (path) | Folder with the traineddata files, e.g. ~/.tool-agents/screener/tessdata    |
            | ocr.tesseractPageSegMode      | integer 0..13 | Tesseract --psm, e.g. 6 (single uniform block)                              |
            | ocr.languageCorrection        | bool          | Vision language correction                                                  |
            | output.preserveFormat         | bool          | Starting position of the overlay's format switch: true = preserve the on-screen layout, false = plain sequential text (replaces output.preserveLineBreaks from 0.1.0) |
            | output.greekMonotonic         | bool          | Convert polytonic Greek diacritics to monotonic                             |
            | output.greekCorrection        | bool          | Repair Greek look-alike letters/accents/digits; needs the macOS Greek spelling dictionary |
            | keyboard.moveUp/moveDown/moveLeft/moveRight | string | Plain keys (no modifiers), e.g. "up"; move the crosshair / jump between lines |
            | keyboard.defaultStepPoints    | number        | Crosshair step for plain arrows, > fineStepPoints, e.g. 20                  |
            | keyboard.fasterModifier       | string        | cmd \| ctrl \| option \| shift — even faster movement (free mode), e.g. shift |
            | keyboard.fasterStepPoints     | number        | Step with fasterModifier, > defaultStepPoints and <= 2000, e.g. 100         |
            | keyboard.fineModifier         | string        | cmd \| ctrl \| option \| shift — precise movement (free mode); must differ from fasterModifier, e.g. option |
            | keyboard.fineStepPoints       | number        | Step with fineModifier, > 0, e.g. 2                                          |
            | keyboard.extendModifier       | string        | cmd \| ctrl \| option \| shift — extend the line selection (text mode)       |
            | keyboard.anchor               | string        | Drop / clear the selection anchor, e.g. "space"                            |
            | keyboard.confirm              | string        | Capture the keyboard selection, e.g. "return"                              |
            | keyboard.nextScreen           | string        | Move keyboard focus to the next display, e.g. "tab"                        |
            | keyboard.toggleTextMode       | string        | Switch between free and text mode, e.g. "t"                                |
            | keyboard.toggleFormat         | string        | Flip the format switch (preserved / plain) for this capture, e.g. "f"      |
            | keyboard.startInTextMode      | bool          | Open the overlay directly in text mode                                     |

            All overlay keys (keyboard.* and hotkeys.cancel) must be distinct.
            | feedback.toast                | bool          | Show the "Copied N characters" HUD                                          |
            | feedback.toastDurationSeconds | number 0..30  | Toast display time (exclusive of 0)                                         |
            | feedback.sound                | bool          | Play a sound on success (and "Basso" on failure)                            |
            | feedback.soundName            | string        | A name from /System/Library/Sounds, e.g. "Tink"                             |
            | history.size                  | integer 1..500| Captures kept in the in-memory menu history                                 |
            | overlay.dimOpacity            | number 0..0.9 | Overlay darkness, e.g. 0.12                                                 |

            Hotkey syntax: modifiers cmd|command, ctrl|control, option|opt|alt, shift joined with "+"
            and a final key: a–z, 0–9, f1–f20, escape|esc, return|enter, tab, space, delete,
            forwarddelete, left, right, up, down, home, end, pageup, pagedown, minus, equal,
            leftbracket, rightbracket, semicolon, quote, comma, period, slash, backslash, grave.

            The standard four-tier env-var resolution chain does not apply: config.json is the
            single source of truth. ~/.tool-agents/screener/.env exists only to satisfy the standard
            per-tool folder layout and carries no active variables.
        </configuration>

        <examples>
            # Install (installs tesseract too)
            brew tap BikS2013/screener && brew install --cask screener
            open -a screener     # first launch: "Create Config from Example"
            # Grant Screen Recording on first capture, then quit and reopen screener.

            # Verify configuration / OCR without the GUI
            /Applications/screener.app/Contents/MacOS/screener --check-config
            /Applications/screener.app/Contents/MacOS/screener --ocr-file ~/Desktop/shot.png

            # Release: docs/design/release-runbook.md (build.sh + package.sh, Homebrew tap commit)

            # Usage
            # 1. Press hotkeys.activate (default example ⌃⌥⌘T) — every screen dims slightly.
            # 2. Drag a rectangle over the text on any screen; release to OCR + copy.
            #    Keyboard: ↑↓←→ move 20 pt (⇧ 100 pt, ⌥ 2 pt), Space anchor, arrows stretch, ⏎ capture.
            #    T switches to text mode: arrows jump between text lines, ⇧+arrows extend, ⏎ capture.
            #    ⇥ moves to the next screen. F flips the format switch: screen format / plain text.
            #
            # Headless OCR in either format
            #   /Applications/screener.app/Contents/MacOS/screener --ocr-file shot.png --format plain
            # 3. Press hotkeys.cancel (⎋) or right-click to dismiss without capturing.
            # 4. Press hotkeys.showHistory (⌃⌥⌘H) to re-copy a recent capture.
            # 5. Settings… in the menu edits config.json (click a hotkey field, press the new combo).
        </examples>
    </info>
</screener>
