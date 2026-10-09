<structure-and-conventions>
## Structure & Conventions — Documentation Map

<!-- Maintained automatically. The master copy lives at
     ~/.claude/structure-and-conventions.md (claude-workdocs repo) and the SessionStart
     hook ~/.claude/scripts/sync-claude-md.sh keeps this copy of the block up to date —
     edit the master, never this block. The block is committed with the repository on
     purpose: it tells anyone (human or agent) working with this repo where the
     project's documentation lives and how to read and maintain it. -->

### Where the documentation lives

- `docs/plans/` — every plan, one file per plan, named `plan-NNN-<indicative-description>.md`.
- `docs/design/` — all other planning and design documents:
  - `project-design.md` — the complete, always-current project design; update it with every new design or design change.
  - `project-functions.md` — the registry of all functional requirements and feature descriptions.
  - `configuration-guide.md` — the project's configuration guide, when one exists (structure below).
- `docs/reference/` — all reference material collected for the project.
- `docs/refined_requests/` — every refined request specification (create the folder if missing), one file per request named `refined-request-NNN-<slug>.md`. `NNN` is a zero-padded three-digit sequential number: the next number is the highest `NNN` already present in the folder plus one, starting at `001` — and when the category has an archive history branch, the archive's numbering counts too (see "Archiving historical documents" below). `<slug>` is the request slug reused by all downstream artifacts of the same request.
- `docs/prompts/` — every prompt created while working on the project (create the folder if missing), one file per prompt named `NNN-<indicative-description>.md`. `NNN` is a zero-padded three-digit sequential number: the next number is the highest `NNN` already present in the folder plus one, starting at `001` — and when the category has an archive history branch, the archive's numbering counts too (see "Archiving historical documents" below). The description states the prompt's use and purpose.
- `docs/tools/<tool-name>.md` — one dedicated documentation file per project tool.
- `test_scripts/` — every test script goes here; create the folder if it doesn't exist.
- `Issues - Pending Items.md` (project root) — the register of every issue, pending item, inconsistency, or discrepancy detected while working on the project. Pending items come first (most critical and important on top), completed items after. Whenever a defect or issue is fixed, check this file for an item to remove.

### How to use the documentation

- Every time an issue is solved, it must be resolved AND both the issue and the solution must be thoroughly documented.
- This file's "Tools" section (when present) lists each project tool with a one-or-two-sentence description of what it is capable of and the relative path to its dedicated documentation file under `docs/tools/` — retrieve the full documentation from there whenever it is needed. Full tool documentation must never be inlined into this file.
- Before writing any code script, consult the "Tools" section and the documentation under `docs/tools/` to check whether the planned code fits the scope of an existing tool. If so, implement it as an extension of that tool; otherwise build a generic, abstract version of the code as a new tool in the project's toolset, document it under `docs/tools/`, and reference it in the "Tools" section. The goal is to progressively grow the tools needed to test, evaluate, generate data, collect information, etc., and reuse them consistently.

### Archiving historical documents (history branches)

- A project MAY move accumulated historical, write-once process artifacts — deployment reports, codebase scans, refined requests, plans, session handoffs, and similar — off the default branch to keep its documentation lean. Living, authoritative documents (`project-design.md`, `project-functions.md`, the guides, tool docs, the issue register) are never archived.
- Each archived category gets a dedicated **orphan, docs-only branch** named `<category>-history`, whose tree contains ONLY that category's files at their original repository paths — so retrieval paths never change: `git show <category>-history:<original-path>`, no branch switching required. A pointer note/README stays in the category's folder on the default branch stating the branch name, the retrieval command, and (for numbered categories) the next number. Archive branches are append-only: never rebase, rewrite, delete, or merge them.
- **Numbering across the archive**: for every `NNN`-numbered folder, the next number is `max(highest NNN in the folder, highest NNN on the category's archive branch) + 1`. Before creating the FIRST document of a numbered category, check whether an archive branch exists for it (the folder's README/pointer note, or `git branch --list --all '*-history'`) and continue from the archive's highest number — never restart at `001`, never reuse an archived number. The archive branch is authoritative over the pointer note's recorded "next number" if they disagree.
- **Migration** runs in a temporary linked worktree so the main checkout — and any uncommitted changes in it — is never disturbed: `git worktree add <tmp> <category>-history` (first-time archiving: `git worktree add --detach <tmp> <default-branch>`, then inside it `git switch --orphan <category>-history` and `git checkout <default-branch> -- <category-paths>`); bring the new artifacts over at their original paths and commit ONLY the category's files; then on the default branch `git rm` the migrated files, update the pointer note, and commit referencing the archive commit. Verify with `git ls-tree -r <category>-history --name-only` and a `git show` spot-check.
- The project's concrete category → branch registry (which categories are archived, under which branch names) is project-specific and lives OUTSIDE this synced block — typically a "Document Archiving Strategy" section in the project's CLAUDE.md.

<configuration-guide>
- A configuration guide, when requested, is created at `docs/design/configuration-guide.md` and explains:
  - When multiple configuration options exist (config file, env variables, CLI params, etc.), what the options are and the priority of each one.
  - The purpose and use of each configuration variable.
  - How the user can obtain such a configuration variable.
  - The recommended approach for storing or managing the variable.
  - Which options exist for the variable and what each option means for the project.
  - Any default value the parameter has.
  - For configuration parameters that expire (e.g., PAT keys, tokens), propose adding a parameter that captures the expiration date, so the app or service can proactively warn users to renew.
</configuration-guide>

</structure-and-conventions>

# screener

A native macOS menu-bar app in Swift. A global hotkey dims every screen slightly, the user drags a rectangle,
and the text inside it is OCR'd and copied to the clipboard.

- Language: Swift 6 toolchain (Swift 5 language mode), SwiftPM, macOS 14+. It is written in Swift at the user's
  explicit request, which overrides the TypeScript default for tools.
- Build / test: `swift build`, `swift test`.
- App bundle: `screener.app`, bundle id `com.local.screener` (sibling convention: `com.local.untype`, `com.local.ntakker`),
  installed in `/Applications`. Build and release layout follows Jumpee: `build.sh` (holds `VERSION=` / `BUILD=`) and `package.sh`
  at the root, output in `build.noindex/` and `dist/`. Release with
  `CODESIGN_IDENTITY=2C7D6068C232BA74073D56085DDBB04E5F14DF30 NOTARY_PROFILE=screener-notary bash package.sh`
  (see `docs/design/release-runbook.md`). Two Developer ID identities share one name, so sign by SHA-1.
  `CODESIGN_IDENTITY` has no default (no-fallback rule; `-` = explicit ad-hoc). Never install an ad-hoc build: it changes the
  TCC identity and drops the Screen Recording grant.
- Releases: GitHub `BikS2013/screener` (public), tags `v<version>` from 0.2.1 (earlier: `v0.1.0-b1`, `v0.2.0-b3`),
  assets `screener-<version>.zip` (used by the cask), `.dmg`, `SHA256SUMS`.
- Headless checks: `.build/debug/Screener --check-config`, `.build/debug/Screener --ocr-file <png>`.
- Config: `~/.tool-agents/screener/config.json`. Every key is required and validated in `ConfigStore.validate`.
  There are no defaults (no-fallback rule). A new config key must go into `AppConfig`, `validate`,
  `config.example.json`, the Settings window and `docs/tools/screener.md`.
- OCR: Apple Vision cannot read Greek, so in `auto` mode Tesseract (`ell+eng`) runs in parallel and wins when Greek is present.
  `GreekCorrector` then repairs look-alike letters, accents and digits, using NSSpellChecker on the main actor.
- Overlay: `OverlayController` owns the mouse and keyboard state for all screens: free mode (crosshair + anchor)
  and text mode (Vision line boxes + `LineNavigator`).
- `Warmup` hides Vision's system-wide ~20 s model load (it runs when the config loads and when the overlay opens).
- Open issues and the dependency vetting log: `Issues - Pending Items.md`.

## Homebrew Tap Convention

- Follows Jumpee (`BikS2013/homebrew-jumpee`). The tap that `brew tap BikS2013/screener && brew install --cask screener`
  clones is https://github.com/BikS2013/homebrew-screener. It receives one commit `screener <version>` per release, made in
  Homebrew's clone of the tap (`brew --repo biks2013/screener`) and pushed. `homebrew-tap/` here is a plain copy, not a subtree.
- The cask (`homebrew-tap/Casks/screener.rb`) is generated by `package.sh`, never hand-edited: version `<version>`, release zip URL,
  post-install notification, caveats with the permission and every hotkey. Keep the caveats in sync with hotkey changes.
- Full procedure: `docs/design/release-runbook.md`, step 7c.

## Tools

- **screener**: native macOS menu-bar app that captures a user-selected screen region, OCRs it (Apple Vision /
  Tesseract, English + Greek auto-detected) and copies the recognised text to the clipboard.
  See `docs/tools/screener.md`.
