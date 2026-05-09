# First-Launch / Reset QA Checklist

Tracks Phase 1.5 of the v1.0.0 release plan (issue #58, parent #53).

Run on a real iPhone with the **Release** archive installed via TestFlight or
Xcode Run (Release scheme). The goal is to verify clean onboarding, correct
permission prompt order, and zero crashes against an empty SwiftData store.

---

## Pre-flight

- [ ] Install the build to a real device (TestFlight or Xcode → Product → Archive → Distribute → Development).
- [ ] If the app was previously installed: **delete it from the home screen** (long-press → Remove App → Delete App). This wipes both the SwiftData store and `UserDefaults`.
- [ ] In **Settings → Placelore**, confirm the entry is gone after deletion (it should be — listed only after first install).
- [ ] Force-stop any old build still in App Switcher.

## Cold launch

- [ ] Launch the app from the home screen (not Xcode).
- [ ] App opens to the **Tracking** tab without a splash crash.
- [ ] **Prompt 1 — Notifications:** "Placelore Would Like to Send You Notifications" appears within ~1s. Tap **Allow**.
  - Source: `ContentView.onAppear` → `NotificationManager.shared.requestAuthorization()`.
- [ ] No location prompt yet (tracking is `.disabled` by default — confirmed in `TrackingState.default`).
- [ ] Tracking chip shows **Disabled** (gray location-slash icon).

## Empty-store smoke test (no permissions yet)

Walk every tab and confirm no crash, no console assertion, no missing-data ugliness:

- [ ] **Tracking** — shutter button visible, tappable. Tracking chip = Disabled.
- [ ] **Logbook** — empty placeholder (`ContentUnavailableView`). No crash.
- [ ] **Map** — map renders, blue user-dot only after location permission. No place pins. No crash.
- [ ] **Search** — empty placeholder. Type a query → "No Results". No crash.
- [ ] **Settings** — opens. "Clear Data" disabled (places + visits empty). Storage size shows. Raw sample count = 0. **Export Raw Samples** present but exporting an empty file is fine.

## Permission prompt 2 — Location

- [ ] Tap the **Tracking chip** → **Enable Tracking** in the sheet.
- [ ] iOS shows: "Allow Placelore to use your location?" with **Allow Once / While Using App / Don't Allow** options.
  - This is iOS 13+ behavior even though we call `requestAlwaysAuthorization()` — When-In-Use is shown first.
  - Verify the usage string matches `NSLocationWhenInUseUsageDescription` from `Info.plist`:
    > "Placelore uses your current location to log the place you are visiting and attach it to your notes."
- [ ] Tap **Allow While Using App**. Tracking chip flips to **Active** (green).
- [ ] No crash, no immediate Always-upgrade prompt (iOS only shows it after a heuristic delay / background-use observation).

## Permission prompt 3 — Camera

- [ ] Tap the **shutter** button on the Tracking tab.
- [ ] iOS shows: "Placelore Would Like to Access the Camera"
  - Verify the string matches `NSCameraUsageDescription`:
    > "Placelore uses the camera to attach photos to your visits and journal entries for a place."
- [ ] Tap **Allow**. Camera opens.
- [ ] Cancel out of camera. No crash on dismiss.

## Always-authorization upgrade (later)

iOS does **not** prompt for Always immediately. To force the upgrade prompt:

- [ ] Lock the device with the app backgrounded for a few minutes.
- [ ] Walk a short distance (or use Xcode → Debug → Simulate Location to move).
- [ ] On next foregrounding, iOS may surface "Placelore has been using your location in the background. Continue allowing?" — verify the **Always** option uses `NSLocationAlwaysAndWhenInUseUsageDescription`:
  > "Placelore uses your location in the background to automatically detect the places you visit, so your logbook stays up to date without you opening the app."
- [ ] If the prompt does not appear within a session, this is acceptable — iOS schedules it on its own. Document outcome.

## Termination + relaunch

- [ ] Force-quit the app from the App Switcher.
- [ ] Relaunch.
- [ ] No crash. Tracking state persists (Active if it was Active).
- [ ] No duplicate permission prompts.

## Background relaunch (already-tracking)

- [ ] With tracking enabled, leave the app and walk ≥80m away from the launch spot, then return.
- [ ] Reopen — no crash. Visit detection continues normally (covered separately by Phase 1.1).

## Final verification

- [ ] No `os_log` errors visible in Console.app filtered by subsystem `dev.placelore.app` and level **Error**.
- [ ] No `fatalError` hit. (The only one is `PlaceNotesApp.init` after a second store-create failure — should never fire on a clean install.)
- [ ] Settings app → Placelore shows: Location = Always (or While Using), Notifications = On, Camera = On.

---

## Audit findings (code paths reviewed)

These were verified before running the device test. Track regressions if any of these change.

| Area | Status | Notes |
|------|--------|-------|
| `Info.plist` permission strings | ✅ | `NSLocationAlways*`, `NSLocationWhenInUse`, `NSCamera` present. `NSPhotoLibrary*` not needed — `PhotosPicker` is out-of-process and `UIImagePickerController` uses `.camera`. |
| `ITSAppUsesNonExemptEncryption` | ✅ | Set to `false` in `Info.plist`. |
| Force-unwraps in hot paths | ✅ | Only `applicationSupportDirectory.first!` and `documentDirectory[0]` — both Apple-guaranteed. |
| `fatalError` reachability | ⚠️ acceptable | One in `PlaceNotesApp.init` after a second `ModelContainer` create failure following a wipe-and-retry. Disk-full / corrupted-FS edge case only. |
| Empty-store views | ✅ | `LogbookView`, `SearchPlacesView`, `FrequentPlacesView`, `ReportView` all use `ContentUnavailableView` when collections are empty. `FrequentPlacesMapView` renders only `UserAnnotation` when `places` is empty. |
| Default tracking state | ✅ | `TrackingState.default = .disabled` — first launch never auto-starts monitoring. |
| Permission prompt order | ✅ documented | Notifications (immediate `onAppear`) → Location WhenInUse (on Enable Tracking) → Camera (on shutter) → Location Always upgrade (later, iOS-driven). |

## Out of scope for 1.5

- Background dwell detection over 30+ min (covered by Phase 1.1).
- Force-unwrap and `print` sweep (Phase 1.2).
- Build configuration audit (Phase 1.3).
