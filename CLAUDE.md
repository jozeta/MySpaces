# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

MySpaces is a macOS menu-bar app that gives desktops (Spaces) real names and shows them in
Mission Control, the menu bar and a switch panel, without patching the system (SIP on, nothing
injected into the Dock). Swift package, macOS 27+, Xcode 27 / Swift 6.4, single display only.

## Commands

```sh
swift test                  # unit tests for Sources/MySpacesCore (Tests/MySpacesCoreTests, with Fixtures/)
scripts/build-app.sh        # build/MySpaces.app, signed with "Apple Development" (override: MYSPACES_SIGN_IDENTITY)
open build/MySpaces.app
scripts/release.sh          # Developer ID build + notarized zip (needs a notarytool profile)
```

Run `docs/release-checklist.md` (manual checks) before releases and after macOS updates.
Permissions: Device Control (Accessibility) for switching, Screen Recording for the Mission
Control overlay. Rebuilding with the same signing identity keeps granted permissions.

## Architecture

- `Sources/MySpacesCore/`: all testable logic, no AppKit UI. Desktop list parsing
  (`SpacesParser`, `Space`, `SpaceRows`, `SpacesController`), names (`NameStore`, `NameFit`,
  `LabelMapper`), label recognition (`StripTextRecognizer`, Vision), overlay timing
  (`CaptionFingerprint`, `OverlayScanGate`, `LayoutStabilizer`, `ScanSlot`, `RestingOffset`),
  background patching (`BackgroundSampler`), switching (`NavigationPlanner`, `Hotkeys`).
- `Sources/MySpaces/`: the app shell: `MenuBar/`, `Overlay/` (click-through name windows over
  Mission Control), `Switch/` (panel on desktop change), `Settings/`, `System/`.

How it works: reads desktops read-only from the window server (stable IDs, so names follow
reordering); when Mission Control opens, captures the Spaces-bar strip and OCRs "Desktop N" labels;
draws each name in its own window with a background rebuilt from neighbouring pixels (solid pill
when too busy); a live stream is checked up to 60 fps against a pixel fingerprint to show, follow
or hide names; switching sends the user's Mission Control keyboard shortcuts.

## Rules

- Put new logic in `MySpacesCore` with tests; keep `MySpaces` a thin UI layer.
- No private-API injection, no Dock patching, nothing that needs SIP off.
- Never save or send screen captures; frames are used in memory only.
- Persistent files: `~/Library/Application Support/MySpaces/names.json` (keep backward
  compatible) and `layouts-v4.json` (a cache: bump the version suffix instead of migrating when
  the format changes).
- Label recognition currently assumes English "Desktop N" labels; don't break that path when
  adding localisation.
