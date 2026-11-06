# Phase 6 Bug Fixes — Root Causes & Solutions

| # | Problem | Root cause | Solution |
|---|---------|-----------|----------|
| 1 | Spotify buttons did nothing | `IslandPanel` is a non-activating panel; the first click was consumed for activation (`acceptsFirstMouse` false). AppleScript ran synchronously on the main thread, errors were swallowed, and the app bundle lacked the Apple Events entitlement. | `IslandHostingView.acceptsFirstMouse = true`; commands run off-main via `NSAppleScript` → `/usr/bin/osascript` → MediaRemote fallback; optimistic UI update followed by immediate re-poll (120 ms + 470 ms); `package-app.sh` signs with `com.apple.security.automation.apple-events`; Previous resets position first so it really skips tracks. |
| 2 | Tabs hidden behind physical notch | Expanded panel started at the screen top, so the first row (tabs) sat under the camera housing. | `NotchGeometry.notchSafeTopInset` (computed from `safeAreaInsets`) drives layout: a header row flanks the notch (wings), tabs and content start below it. Expanded height = inset + 295. |
| 4 | Text ~30% clipped | Content was padded from y=0 inside a pill of notch height; the notch mask and `.clipped()` cut text; fixed-height rows with no `fixedSize`. | Collapsed/Activity split into left wing / notch gap / right wing; Peek content placed below the inset; `lineLimit` + `fixedSize(vertical:)` on text. |
| 3 | Lyrics lag | 250 ms stepping, 1 s poll, IPC latency. | Monotonic anchor (`systemUptime`) interpolated at 50 ms with 120 ms lead compensation; re-anchored on every Spotify poll/notification; slide+fade transition keyed on line index. |
| 5 | Manual telemetry refresh | Sampling only on button press. | Single `Task` polling every 2 s (CPU delta ticks, RAM, battery, disk), skipped while app hidden; button removed. |
| 6 | Collapsed artwork | — | Circular artwork + `Circle().trim` ring bound to `playbackProgress` (anchor-based, freezes on pause, resets on track change). |

Note: Spotify artwork falls back to the Spotify oEmbed endpoint using the track ID when AppleScript artwork is empty.
