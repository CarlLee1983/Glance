# Glance Development

## Requirements

- macOS 14 or newer for the menu bar app target.
- Swift 5.9 or newer.
- Xcode/Xcode command line tools.
- XcodeGen only if regenerating or building through `Glance.xcodeproj`.

## Common Commands

```bash
swift test
swift build --product Glance
swift run glance-cli
```

`swift test` is the primary verification command for `GlanceCore`.

`swift build --product Glance` verifies the SwiftUI app target compiles through SwiftPM.

`swift run glance-cli` is useful for a quick real-system sampling smoke test.

## Xcode Project Build

The repository includes `project.yml` for XcodeGen.

```bash
xcodegen generate
xcodebuild -project Glance.xcodeproj -scheme Glance -destination 'platform=macOS' build
```

Open the built `Glance.app` from Xcode build products to run the menu bar app.

## Local App Bundle Restart

For local development, an installed user app may exist at:

```text
/Users/carl/Applications/Glance.app
```

After `swift build --product Glance`, update and restart that local app with:

```bash
cp .build/debug/Glance /Users/carl/Applications/Glance.app/Contents/MacOS/Glance
chmod +x /Users/carl/Applications/Glance.app/Contents/MacOS/Glance
pkill -x Glance || true
open /Users/carl/Applications/Glance.app
```

Confirm the running process:

```bash
pgrep -fl Glance
shasum -a 256 .build/debug/Glance /Users/carl/Applications/Glance.app/Contents/MacOS/Glance
```

The two checksums should match if the installed app bundle contains the latest build.

## Testing Strategy

The project keeps most behavior testable in `GlanceCore`.

| Area | Test Focus |
| --- | --- |
| Samplers | diff math, nil source handling, sorting, limits |
| App grouping | `.app` bundle grouping and non-app fallback behavior |
| Memory app rows | identity grouping (app bundle / executable path), source classification, solo pid |
| Safety | cleanup, trash, uninstall, and symlink escape rejection |
| Health | score bands and penalty math |
| Formatting | user-facing metric strings |
| History | ring buffer capacity and metric recording |

Before claiming a change is complete, run the smallest relevant focused test first, then `swift test`. For UI-impacting model changes, also run `swift build --product Glance`.

## Adding A Metric

Prefer this shape:

1. Add immutable model data under `Sources/GlanceCore/Model`.
2. Add a raw source protocol or bridge under `Sources/GlanceCore/Bridge` when system APIs are involved.
3. Add sampler logic under `Sources/GlanceCore/Sampling`.
4. Thread the result through `SystemSnapshot`, `SystemSampler`, and `MetricsStore`.
5. Add formatting/status helpers only if reusable.
6. Add SwiftUI rendering under `GlanceApp/Dropdown` or `GlanceApp/MenuBar`.
7. Cover core behavior with tests before UI polish.

## Adding A Destructive Action

Destructive actions must be designed around safety first:

- Use explicit allowlists.
- Normalize paths before comparison.
- Reject symlinks when they can escape the allowed root.
- Prefer moving user-owned app artifacts to trash instead of permanent deletion.
- Keep pure safety decisions in `GlanceCore`.
- Inject the actual delete/trash action so tests can verify behavior without touching real user files.

## Documentation Rules

- Keep README as the short entry point.
- Put durable implementation knowledge in `docs/*.md`.
- Keep historical design/spec/plan artifacts under `docs/superpowers`.
- Update `docs/DECISIONS.md` when a product or architecture decision would otherwise be rediscovered.
