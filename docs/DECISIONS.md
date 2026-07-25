# Glance Decisions

This is a lightweight decision log for choices that future work should not reopen without new evidence.

## Direct Distribution, Not Mac App Store

Decision: distribute Glance directly rather than through the Mac App Store.

Why:

- Thermal and power readings use private macOS interfaces.
- Menu bar diagnostic tooling benefits from system-level readings that App Store rules may reject.

Consequence:

- Packaging, signing, notarization, and update flow must be handled outside the App Store if the project is distributed.

## Keep GlanceCore UI-Free

Decision: keep `GlanceCore` independent of SwiftUI/AppKit.

Why:

- Sampling math, grouping, safety rules, and health scoring need unit tests.
- AppKit side effects make tests brittle.
- CLI and app targets can share the same data layer.

Consequence:

- UI-only concerns such as `NSWorkspace` icons and `NSAlert` confirmations stay in `GlanceApp`.

## Do Not Add A Memory Purge Button

Decision: do not implement `sudo purge`, "free memory", or similar memory optimization actions.

Why:

- macOS already manages inactive/cache memory.
- Purging cache can make the system slower by forcing data to be read from disk again.
- `sudo` is too much authority for a menu bar monitor.

Preferred direction:

- Identify high-memory apps and services.
- Show source details.
- Offer graceful app termination for eligible `.app` bundles.

## Group Memory By Identity (App Bundle Or Executable Path)

Decision: group memory rows by identity — `.app` processes under their bundle, non-app processes under their **executable path**. Different paths are never merged.

> Supersedes the earlier "keep non-app processes separate by pid" decision. Grouping only apps caused genuine multi-process consumers (`node`, `claude`) to be scattered across many sub-limit rows and vanish from the top list. The original name-collision worry does not apply, because the group key is the full executable path, not the process name. Full rationale and evidence: `docs/adr/0001-aggregate-non-app-processes-by-executable-path.md`.

Why:

- Browsers, Electron apps, Xcode, and CLI tools alike spawn many processes; grouping by identity reflects "how much is this one program using" better than per-pid rows.
- Same path means the same program's instances; different paths stay separate, so unrelated `node`/daemon processes are never incorrectly summed.

Consequence:

- Memory list rows carry source kind (origin), executable path, and a solo pid (single-process rows only) to explain entries. Kind and terminability are orthogonal — see `docs/adr/0002-terminate-eligibility-by-running-apps-membership.md`.

## Cleanup Uses Permanent Delete; Uninstall Uses Trash

Decision: cleanup category contents are permanently deleted, while app uninstall and disk analyzer delete actions move items to trash where practical.

Why:

- Cleanup categories are explicit disposable cache/log/trash roots.
- App uninstall and disk analyzer actions are broader and benefit from user recovery.

Consequence:

- Cleanup requires clear confirmation text and strict allowlists.
- Uninstall/trash flows need safety checks and skip unsafe paths.

## Prefer Conservative File Matching

Decision: app related-file detection uses bundle ID matching and known support directories instead of broad fuzzy search.

Why:

- Fuzzy deletion risks unrelated user data.
- Bundle ID matching is explainable and testable.

Consequence:

- Some related files may remain after uninstall. That is preferable to deleting unrelated files.

## Keep Feature Work Test-First In Core

Decision: core behavior changes should start with focused tests where practical.

Why:

- Most project risk lives in sampling math, process grouping, file safety, and state transitions.
- SwiftUI visual changes are harder to unit test, but the data driving them should be verified.

Consequence:

- New model behavior should be covered in `Tests/GlanceCoreTests`.
- UI work should still build with `swift build --product Glance`.
