# Changelog

All notable changes to MySpaces are listed here, newest first.

Releases follow the project's git tags. Entries were reconstructed from the commit history.

## [Unreleased]

- SwiftLint (`.swiftlint.yml`; naming and size rules off for the existing code). CI is waived in
  `.claude-standards` until GitHub runners have Xcode 27

- Ignore macOS, Claude Code and secret files
- Add CLAUDE.md with project guidance for Claude Code
- Add security policy

## [1.0.2] - 2026-10-19

- fix(release): zip without extended attributes so the app stays signed after any unzip
- fix: Mission Control names stop for good after a desktop switch during a scan

## [1.0.1] - 2026-10-17

- fix: redraw names whose windows were lost; safer permission reset

## [1.0] - 2026-10-15

- Add MySpaces design spec
- Spec: make overlay fallback threshold explicit
- Add MySpaces v1 implementation plan and OCR fixtures
- feat(core): Space model and CGS/plist parser
- feat(core): JSON name store with normalisation and corruption recovery
- feat(core): menu rows and two-refresh name pruning
- feat(core): symbolic hotkey parsing and navigation planning
- feat(core): map Mission Control captions to named desktops
- feat(core): strip-based Vision OCR for Mission Control captions
- feat(core): background sampling for native-look caption patches
- feat(app): menu-bar popover with Space list and inline rename
- feat(app): switch Spaces via posted shortcuts with Accessibility flow
- feat(app): Mission Control name overlay
- feat(app): settings, diagnostics and launch at login
- chore: release signing, notarization and checklist
- fix: overlay safety rule, scan ordering, fallback pruning, runtime CGS lookup
- chore: ignore SwiftPM .build directory
- fix: popover alignment, permission flow, faster flicker-free overlay
- fix: popover off-screen, permission recovery, overlay timing via caption fingerprint
- chore: log permission state at launch, on change, and tccutil reset results
- feat: fade names in with Mission Control's caption animation
- fix: names no longer float or land on the wrong desktop while Mission Control animates
- fix: names no longer twitch, blink or show as boxes in Mission Control
- fix: native-looking names that keep up with Mission Control's animations
- fix: names survive adding or removing a desktop in Mission Control
- feat: desktop name when switching, About/Quit, fading long names
- fix: read every caption with six or more desktops
- docs: README with screenshots, MIT license, gitignore; round switch panel
- fix: longer fade for long names on the switch panel
- fix: names no longer flicker in Mission Control's thumbnail view
- docs: screenshots with the current desktop names
- fix: names appear quickly again after renaming or adding desktops
- fix: names stay at the bar's edge, and survive reordering desktops
- fix: reordered desktops keep their names; faster names on a new desktop; quick fades
- fix: names stay put and come back when desktops are moved, added or removed
- chore: keep internal planning notes out of the repository
