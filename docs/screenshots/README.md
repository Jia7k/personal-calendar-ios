# Screenshot capture notes

These are unedited captures of the running app, not design mockups.

- App source: `186619b02bba772275d74d5e0a27728deb306634` (`codex/daily-qol-polish`).
- Captured: September 12, 2026.
- Device: iPhone 17 Pro simulator, iOS 26.5, portrait, default text size.
- Resolution: 1206 × 2622 pixels per PNG.
- Appearance: the app's Harbor & Linen light appearance.
- Status bar: simulator override set to 9:41, Wi-Fi, and a full battery. This does not change the demo clock used by the app.
- Privacy: a fresh simulator ran with `-ui-testing -demo-daily-qol -demo-daily-task-rescue`. These options use in-memory demo services instead of live Calendar or Reminders content. No personal account or provider data was used.

## Reproduce the screens

Build the app for iOS Simulator and launch it with the arguments above. For a direct start on Today, also pass `-demo-today-route`.

1. Capture **Today** and **Tasks** with the supplied demo items.
2. Use **Quick Entry** to enter `Design workshop Monday at 10am`. Capture its Review screen before saving.
3. Save the event and use **Add Another** for `Project sync Tuesday at 11am`, `Study session Wednesday at 10am`, `Team lunch Thursday at 12pm`, and `Weekly review Friday at 11am`.
4. Capture **Month** with today selected, then select the workshop's Monday and switch to **Week**.
5. Open the workshop's event editor. Set the fictional location to `Design Studio, Level 2` and notes to `Bring your sketchbook and laptop. Review the latest concepts together.` Save, then reopen its Week preview and capture **Event details**.

The demo's dates and relative times follow the capture date; later captures will differ. Do not enable failure-injection launch arguments or use a live-data launch for documentation screenshots.

Save each image with `xcrun simctl io <screenshot-simulator-id> screenshot <filename>.png`. Keep the PNGs at their original resolution; the root README controls their display width and links to the originals. Review every image for accidental private information before publishing.
