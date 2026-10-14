# MySpaces — Design Spec

Date: 2026-10-14 · Status: approved in brainstorming, pending written review
Target: macOS 27.0+, Apple Silicon and Intel, SIP enabled, no root.

## 1. Goal

A lightweight, menu-bar-native macOS utility that lets the user name their
desktops (Spaces), switch between them by name, and **see those names in
Mission Control** in place of "Desktop 1", "Desktop 2", …

Visual direction: Nordic minimalism — native SF Pro, SF Symbols line icons,
compact rows, subtle separators, system light/dark. Palette accents: Deep Fjord
`#172A35`, Nordic Mist `#F3F5F2`, Sage `#DCE4DE`, Graphite `#292D30`.

## 2. Feasibility findings (spike, 2026-10-14, macOS 27.0 / 26A428)

| Question | Finding |
|---|---|
| Rename labels through Accessibility? | No. Dock's AX `mc` group has zero children while Mission Control is open (also with `AXEnhancedUserInterface`). |
| Rename labels natively? | Only via code injection into Dock (spaces-renamer/MacForge); requires SIP partially disabled and is documented as broken from macOS 14.4. **Rejected.** |
| Can an app window render above Mission Control? | Yes. Windows with `.canJoinAllSpaces + .stationary` render unscaled above MC, even at `.floating` level. |
| Detect MC open/close? | Dock owns a full-screen layer-20 window only while MC is open. Detected in ~0.15 s open / ~0.5 s close via `CGWindowListCopyWindowInfo`. |
| Locate labels? | Vision text recognition over a **tight (~32 pt) crop** of the caption row reads all labels exactly, including at 1× scale. Tall crops miss or misread small captions. First Vision call ~24 s (cold model) → prewarm at launch; warm ~0.03 s. |
| Full-screen Spaces | Labeled with the app name, not "Desktop N". "Desktop N" numbering skips them (plist `type 4`). |
| Bar state | With a full-screen Space present (or on hover) MC opens with the bar expanded; captions sit below thumbnails (~y 190 pt on a 1490 pt-tall screen) instead of ~y 60 pt. |
| Flash | Labels are not yet rendered ~0.3 s after MC opens → "Desktop N" is visible ~0.5 s before the overlay appears. Accepted. |

**Decision:** MySpaces shows names in Mission Control via an **overlay**:
it detects MC, locates the "Desktop N" captions, and draws the custom name over
them in a native-looking style. This is an overlay, not a true rename, and is
documented as such to users.

## 3. Decisions

| Topic | Decision |
|---|---|
| Distribution | Direct download, Developer ID signed + notarized (no Mac App Store). |
| Mission Control names | Overlay (§2). Native-look style (B); per-label fallback to frosted pill when background is too busy. |
| Full-screen Spaces | Never renamed; shown read-only in the menu with their app name. |
| Switching | Control-N when "Switch to Desktop N" is enabled; otherwise step with Control-←/→. Settings offers "Enable direct switching" (opens System Settings; never rewrites the user's shortcuts). No private switching APIs. |
| Displays | v1 = single display / shared Spaces. Names are keyed per display in storage. If multiple displays with separate Spaces are detected, overlay is disabled on secondary displays and the menu says so. |
| Network / accounts / analytics | None. |

## 4. Architecture

Swift, SwiftUI + AppKit, single app target plus a unit-test target.

### 4.1 Spaces model
- **`SpacesRepository`** — returns the ordered live Space list via
  `CGSCopyManagedDisplaySpaces` (private SkyLight function, read-only).
  Fallback: `com.apple.spaces` preferences (may lag behind Dock).
- **`SpaceChangeMonitor`** — triggers a refresh on
  `NSWorkspace.activeSpaceDidChangeNotification`, popover open, and MC close.
- **`SpaceNameStore`** — JSON at
  `~/Library/Application Support/MySpaces/names.json`, mapping identity key →
  name. Atomic writes.

### 4.2 Menu bar
- **`MenuBarController`** — `NSStatusItem` (monochrome "stacked desktops" SF
  Symbol, no text) + `NSPopover` hosting the SwiftUI list.
- **`SpaceListView`** — header ("MySpaces" / "Your desktops, organized."),
  one compact row per Space: name, secondary "Space N · Current desktop", pencil
  icon for inline rename, checkmark/accent on the current Space. Full-screen
  Spaces: app name, no pencil. Footer: "Manage Spaces…" (Settings), version.
- **`SpaceNavigationService`** — switching per §3.

### 4.3 Mission Control overlay
- **`MissionControlDetector`** — polls at ~10 Hz for Dock's layer-20 window;
  publishes `open`/`closed`.
- **`LabelLocator`** — captures the top screen band with ScreenCaptureKit and
  runs `VNRecognizeTextRequest` (`.accurate`, `usesLanguageCorrection = false`)
  over overlapping ~32 pt horizontal strips; returns `[(text, rect)]`. Vision is
  prewarmed at launch. Rescans when the pointer enters the bar region or the
  previous scan's layout differs.
- **`LabelMapper`** — maps "Desktop N" → Nth `.desktop` Space on that display →
  identity key → name. Ignores any other text.
- **`OverlayRenderer`** — one borderless, click-through window per label
  (`.floating`, `.canJoinAllSpaces + .stationary + .ignoresCycle +
  .fullScreenAuxiliary`). Samples bar pixels left and right of the caption,
  paints a matching patch over "Desktop N", and draws the name in the native
  caption font/colour. If the sampled background variance exceeds a threshold,
  that label uses the frosted pill instead. All overlays hide immediately on MC
  close.

### 4.4 Settings
`SettingsView`: permission status + grant buttons, launch at login
(`SMAppService.mainApp`), "Enable direct switching", diagnostics.

## 5. Data flow and identity

- **Identity key:** the Space UUID. The first desktop on each display has an
  empty UUID → key `main:<displayIdentifier>`. UUID stability across reorder,
  logout/login and reboot must be confirmed in implementation (manual check).
- **Refresh:** repository → `[Space { managedID, uuid, kind: .desktop |
  .fullscreen(appName), displayID, isCurrent }]` → reconciled with the store →
  published view model consumed by popover and overlay.
  - New Space: default "Desktop N" label; nothing stored until renamed.
  - Deleted Space: its name is pruned after it is absent in **two consecutive**
    refreshes.
  - Reorder: names follow the UUID.
- **Rename:** inline edit; Enter saves (trimmed); empty restores default;
  Escape cancels.
- **Overlay cycle:** detector `open` → wait ~0.4 s → locate → map → render;
  rescan on pointer-enters-bar or layout change; `closed` → hide.
- **Safety rule:** if the number of recognised "Desktop N" captions does not
  equal the number of `.desktop` Spaces, draw nothing for that MC session.

## 6. Permissions and error handling

| Permission | Used for | When missing |
|---|---|---|
| Accessibility | Posting switch shortcuts | Clicking a row shows "Allow MySpaces to switch desktops" + button to System Settings. Renaming still works. |
| Screen Recording | Locating MC labels | Overlay off; popover shows a subtle note. Everything else works. |

No prompt at first launch; a dismissible onboarding row in the popover explains
both permissions.

| Failure | Handling |
|---|---|
| Space list unreadable | Fall back to plist; else show "Couldn't read Spaces" + Retry. |
| Switch did not take effect within ~1 s | Inline hint (e.g. enable direct switching). |
| Labels not found in MC | Draw nothing, log, increment miss counter. |
| 5 consecutive misses | Popover shows "Mission Control names aren't working on this macOS version". |
| Corrupt `names.json` | Move to `names.json.bak`, start empty, log. |

Diagnostics view: macOS version, permission states, last Space list, last scan
(result + timing), miss counter, "Copy report". Logging via `os.Logger`
(subsystem `com.myspaces.app`), local only.

## 7. Testing

- **Unit (XCTest, protocol fakes for repository, store, capture, key poster):**
  reconciliation (new / deleted with two-refresh prune / reorder / empty main
  UUID / full-screen interleaved); `LabelMapper` (full-screen interleaved, count
  mismatch → no overlay, OCR noise); navigation strategy (direct vs step count
  and direction, crossing full-screen Spaces); store (round-trip, trim, empty →
  default, corrupt-file recovery).
- **Fixture-based `LabelLocator` tests:** spike screenshots (collapsed bar,
  expanded bar with a full-screen Space) checked in with expected caption text
  and positions.
- **Manual release checklist:** create/delete/reorder Spaces; enter/exit
  full-screen app; logout/login and reboot (names persist); revoke/grant each
  permission; light/dark; busy vs plain wallpaper (pill fallback); hover
  expansion; MC via F3, trackpad gesture and hot corner.

## 8. Out of scope for v1 / known gaps

- Multiple displays with separate Spaces (storage is ready; overlay/menu not).
- Non-English system languages (positional mapping should generalise; untested).
- Renaming full-screen Spaces.
- Global hotkeys, emoji picker, iCloud sync, Mac App Store.
- Hiding the ~0.5 s "Desktop N" flash when MC opens.

## 9. Implementation order

1. Spaces model + store + reconciliation (unit-tested).
2. Menu-bar shell, popover list, inline rename, light/dark.
3. Switching service + Accessibility flow.
4. MC detector, locator (with fixtures), mapper, renderer.
5. Settings, diagnostics, launch at login.
6. Signing, notarization, manual checklist.
