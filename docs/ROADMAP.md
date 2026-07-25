# Glance Roadmap

Glance is currently in a solid utility-app state. The next work should favor documentation, reliability, packaging, and only high-signal product improvements.

## Current Priority

1. Keep documentation current.
2. Preserve safety and test coverage.
3. Improve packaging and local update flow.
4. Add only features that make system diagnosis clearer or safer.

## Good Follow-Up Work

### Packaging And Distribution

- Add a repeatable script for building and updating `~/Applications/Glance.app`.
- Add signing/notarization notes if direct distribution becomes a goal.
- Document or automate Homebrew-style packaging if this becomes public.

Acceptance criteria:

- A fresh clone can build, install locally, restart, and verify the running binary with one documented flow.

### Memory Details

- Add optional row expansion for grouped apps to show child process names and memory.
- Add a copy action for pid/path when diagnosing services.
- Consider showing parent process when it is available and useful.

Acceptance criteria:

- Users can answer "what is this memory row?" without leaving Glance for common app, CLI, and system service cases.

### Disk Analyzer Polish

- Improve large-tree scan progress and cancellation visibility.
- Add clearer skipped-path reporting.
- Consider persistent scan cache controls.

Acceptance criteria:

- A long home-folder scan communicates progress, can be cancelled, and explains skipped paths.

### Observability And Diagnostics

- Add a diagnostics export that captures current snapshot, top processes, and version/build information.
- Keep sensitive data out by default; paths may need redaction or user confirmation.

Acceptance criteria:

- A user can create a useful support/debug artifact without exposing unnecessary private data.

## Possible But Lower Priority

- More menu bar segment display presets.
- More health score explanation details.
- More cleanup categories, if each has a clear safety rule.
- Better visual polish for settings and secondary windows.

## Explicit Non-Goals

- Memory purge / sudo optimize buttons.
- Force quit as the default memory action.
- Broad fuzzy deletion of app support files.
- Mac App Store distribution while private sensor APIs remain in use.
- Turning Glance into a general automation or task runner.

## When To Start A New App Instead

Start a new app when the idea no longer fits one of these Glance goals:

- system monitoring
- local diagnostics
- safe cleanup/uninstall
- macOS menu bar utility workflows

If the next idea is about developer productivity, project analysis, personal knowledge management, or domain-specific business workflows, it should likely be a separate app rather than another Glance feature.
