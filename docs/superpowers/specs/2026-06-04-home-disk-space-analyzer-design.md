# Home Disk Space Analyzer Design

## Purpose

Glance should help explain why disk usage is high, not only report the total used percentage. The first version adds an on-demand home directory analyzer to the existing macOS app. It scans the user's home directory, ranks the largest folders and files, and lets the user reveal items in Finder.

The feature is intentionally read-only. It does not delete, move, clean, or classify files as safe to remove.

## Scope

In scope:

- Add an "Analyze Space..." entry point from the existing Disk section.
- Open a separate SwiftUI analyzer window.
- Scan the current user's home directory (`~`) only when requested.
- Show largest folders and largest files as separate result views.
- Show scan progress, skipped paths, and completion state.
- Reveal a selected result in Finder.
- Keep normal menu bar sampling lightweight while scans run.

Out of scope:

- Automatic deletion or "Move to Trash".
- Background indexing while Glance is idle.
- System-wide scanning outside the home directory.
- Remote volumes, external disk cleanup, or duplicate-file detection.
- Opinionated cleanup recommendations.

## User Flow

1. The user opens the Glance dropdown.
2. The Disk card shows current usage and an "Analyze Space..." action.
3. The action opens a dedicated analyzer window.
4. The analyzer starts scanning the user's home directory.
5. During scanning, the window shows progress:
   - current path when available,
   - number of entries scanned,
   - number of skipped paths,
   - a cancel control.
6. Results update incrementally and remain available after completion.
7. The user switches between "Largest Folders" and "Largest Files".
8. The user selects "Reveal in Finder" for any result.

## UI Design

The analyzer window should feel like a utility panel, not a dashboard. It should be dense, scannable, and focused on the file system evidence.

Window layout:

- Header: title, scan root, status text, and rescan/cancel control.
- Summary strip: scanned item count, skipped path count, total size represented by ranked folders, elapsed time.
- Segmented control: "Folders" and "Files".
- Result table/list:
  - name,
  - formatted size,
  - path,
  - last modified date when available,
  - action button for Reveal in Finder.
- Footer/status area: skipped-path summary and non-fatal error count.

The dropdown Disk section should stay compact. It should not show scan results directly.

## Core Architecture

Add a read-only disk analysis feature to `GlanceCore` so the scan logic can be tested without SwiftUI.

Proposed core types:

- `DiskSpaceAnalyzer`
  - Owns traversal and aggregation.
  - Accepts a root URL, maximum result count, and optional exclusion policy.
  - Emits progress and final ranked results.
- `DiskSpaceScanResult`
  - Contains ranked folder results, ranked file results, skipped paths, and summary counters.
- `DiskSpaceItem`
  - Represents a file or folder result with URL, display name, byte size, kind, and metadata.
- `DiskSpaceScanProgress`
  - Represents scanned count, skipped count, current path, and partial top results.

The App target owns window presentation and Finder integration. `GlanceCore` must not call AppKit.

## Traversal Rules

The initial root is `FileManager.default.homeDirectoryForCurrentUser`.

The analyzer should:

- recursively enumerate the home directory,
- avoid following symlinks by default,
- read file size and modification date through URL resource values,
- aggregate folder sizes from child file sizes,
- keep only the top N folders and files needed for display,
- treat unreadable paths as skipped, not fatal,
- support cancellation.

Hidden files and folders are included because they often contain large caches and developer artifacts. The full path is shown so the user can judge the result.

## Performance

Scanning can be expensive, so the feature must be explicitly user-triggered.

Implementation constraints:

- Scans run off the main actor.
- UI updates are throttled to avoid excessive SwiftUI invalidation.
- Normal system sampling continues independently.
- A scan window can cancel an in-flight scan.
- The first version may compute exact folder sizes with a full traversal; no persistent index is required.

## Error Handling

The scan should continue through non-fatal errors:

- permission denied,
- broken symlink,
- file disappearing during scan,
- metadata unavailable.

Each skipped path should preserve the URL and a concise reason. The UI should summarize skipped paths and expose enough detail for debugging without overwhelming the main results.

## Testing Strategy

Unit tests should use temporary directories and deterministic fixtures.

Required test coverage:

- largest files are sorted by descending size,
- folder sizes include nested child files,
- hidden directories are included,
- symlinks are not followed,
- unreadable or disappearing paths do not fail the whole scan,
- cancellation stops traversal and returns a cancelled state,
- app-level Finder reveal remains outside `GlanceCore`.

Manual verification:

- Open Glance, launch the analyzer from the Disk section, and confirm the menu bar remains responsive.
- Scan a real home directory and verify large known folders appear.
- Reveal at least one file and one folder in Finder.
- Cancel a scan and rescan successfully.

## Acceptance Criteria

- The Disk section has an "Analyze Space..." action.
- The analyzer scans `~` only after the user opens the tool.
- The analyzer shows both largest folders and largest files.
- Results include size and path.
- Reveal in Finder works for files and folders.
- The feature is read-only and offers no deletion action.
- Normal Glance sampling remains responsive during scanning.
- Core scan behavior is covered by unit tests.
