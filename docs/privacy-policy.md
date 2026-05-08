# Placelore Privacy Policy

_Last updated: May 8, 2026_

Placelore ("the app") is an iOS application that helps you keep a personal journal of the places you visit. This policy explains what data the app handles and how.

## Summary

- All your data stays on your device.
- The app does not have a backend server, user accounts, or cloud sync.
- The app does not use analytics or third-party tracking SDKs.
- The app does not share your data with anyone.

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

## Data the app does not collect

- No name, email address, phone number, or account identifier.
- No advertising identifier (IDFA), device fingerprint, or analytics events.
- No crash reports are sent off-device beyond what Apple collects under the system-level "Share With App Developers" setting you control in iOS Settings.

## Data sharing

Placelore does not transmit your data to the developer or to any third party. There is no server to share data with.

## Data retention and deletion

- All data lives in the app's on-device storage. Deleting the app from your device removes all of it.
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
