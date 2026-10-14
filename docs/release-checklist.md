# MySpaces release checklist

Run before every release and after every macOS update. Record macOS version and date.

## Automated
- [ ] `swift test` passes (fixture OCR tests included)

## Spaces and names
- [ ] Rename a desktop; name shows in menu and in Mission Control
- [ ] Create a Space: it appears as "Desktop N" with no stale name
- [ ] Delete a named Space: its name disappears from names.json after two refreshes
- [ ] Reorder Spaces in Mission Control: names follow their Spaces
- [ ] Enter and exit a full-screen app: neighbouring names stay correct; full-screen row is read-only
- [ ] Log out and in: names persist (confirms UUID stability)
- [ ] Reboot: names persist

## Switching
- [ ] Step switching across a full-screen Space works
- [ ] Direct switching works with "Switch to Desktop N" enabled
- [ ] Revoke Accessibility: clicking a row explains and offers the setting; grant restores switching

## Mission Control overlay
- [ ] Opens via F3, trackpad gesture and hot corner
- [ ] Collapsed bar and hover-expanded bar both show names
- [ ] Closing Mission Control leaves no overlay behind
- [ ] Busy wallpaper: pill fallback, no mismatched blocks
- [ ] Revoke Screen Recording: overlay off, popover note shown
- [ ] A name like "Desktop 5" does not confuse rescans

## Appearance and packaging
- [ ] Light and dark appearance
- [ ] Launch at login on/off
- [ ] `scripts/release.sh` completes; `spctl` reports "Notarized Developer ID"
- [ ] Fresh user account: app opens from the zip without Gatekeeper warnings

## Known gaps (v1)
- Multiple displays with separate Spaces: overlay off on secondary displays
- Non-English macOS: untested
- "Desktop N" is visible for ~0.5 s when Mission Control opens
- Collapsed Spaces bar: names longer than ~9 characters are truncated with "…" (full names show once the bar expands)
- With a crowded menu bar, macOS may place the MySpaces icon in the menu-bar overflow
