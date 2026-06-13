# Placelore Privacy Policy

_Last updated: June 13, 2026_

Placelore ("the app") is an iOS application that helps you keep a personal journal of the places you visit. This policy explains what data the app handles and how.

## Summary

- Your places, visits, journal entries, photos, raw location samples, and place-prediction feedback stay on your device.
- The app does not transmit any of your data off your device. (Cloud upload of place-prediction feedback is currently disabled.)
- The app does not have user accounts or cloud sync.
- The app does not use analytics or third-party tracking SDKs.
- The app does not sell your data or share it for advertising.

## Data the app collects

Placelore accesses the following data **only on your device**:

### Location

- The app uses Core Location (including background location and visit monitoring) to detect when you arrive at and leave a place.
- Detected stays are saved as `Place` and `Visit` records in the app's on-device database (SwiftData).
- Raw GPS samples used during stay detection are processed in memory and are not persisted unless you have explicitly enabled the developer raw-sample logging feature for offline analysis. Those samples also remain on your device.

### Photos

- If you attach photos to a journal entry, the app reads the selected images via the system photo picker and stores copies in the app's on-device database alongside your notes.
- The app does not upload photos anywhere.

### Journal entries and place metadata

- Notes, place names, categories, and timestamps you create are stored in the app's on-device database.

### Place-prediction feedback

- If you mark whether a detected place was correct or wrong, the app stores that feedback on your device.
- This feedback stays on your device. Cloud upload of feedback is currently disabled, so no feedback leaves your device.
- If feedback upload is re-enabled in a future version, this policy will be updated first, and the App Store privacy details will be changed to declare it before that version ships.

## Data the app does not collect

- No name, email address, phone number, or account identifier.
- No advertising identifier (IDFA), device fingerprint, or analytics events.
- No crash reports are sent off-device beyond what Apple collects under the system-level "Share With App Developers" setting you control in iOS Settings.

## Data sharing

Placelore does not transmit your data off your device. It does not sell your data, share it for advertising, or use third-party tracking SDKs. (Map search and reverse geocoding are performed through Apple's MapKit and Core Location services to turn coordinates into place names; these are handled by Apple under its own privacy policy.)

## Data retention and deletion

- Places, visits, journal entries, photos, raw location samples, and locally queued feedback live in the app's on-device storage. Deleting the app from your device removes the on-device copy.
- You can delete individual places, visits, journal entries, and photos from within the app at any time.

## Permissions used

- **Location (When In Use / Always):** required to detect arrivals, departures, and dwell time at places. The "Always" authorization is what enables passive logging while the app is in the background.
- **Photo Library:** required only when you choose to attach a photo to a journal entry.
- **Camera** _(if applicable in your build):_ required only if you choose to take a photo from within the app.

You can revoke any of these permissions at any time in the iOS Settings app.

## Children

Placelore is not directed at children under 13 and does not knowingly collect data from them. Because the app does not collect personal information at all, no special children-data handling is needed.

## Changes to this policy

If this policy changes, the updated version will be posted at the same URL with a new "Last updated" date.

## Contact

Questions about this policy can be sent to **ychu0824@gmail.com**.
