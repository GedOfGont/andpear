# NotifyBridge Privacy Policy

_Last updated: 2026-11-24_

NotifyBridge forwards notifications from your Android phone to your own Mac. This policy explains what the app does with your data.

## What the app accesses
- **Notifications (Notification Access permission).** The app reads the notifications posted on your phone (app name, title, text, app icon) so it can show them on your Mac. You choose which apps are forwarded.
- **Clipboard (only when you ask).** Text you share to the app via the Android share sheet, or choose to send from the app, is sent to your Mac. If you enable it, text copied on your Mac is placed on your phone clipboard.
- **Battery level and charging state** of the phone, shown in the Mac app.
- **Local network access** to find and connect to your Mac.

## Where the data goes
Data is sent **directly from your phone to your Mac** over your local network. Everything is encrypted end to end with a 256-bit key (AES-256-GCM) created when you pair the two devices by QR code. The key stays on your devices.

NotifyBridge has **no servers that receive your data**, no accounts, no analytics, no advertising and no third-party trackers. We cannot see your notifications.

## What is stored
- On the phone: your settings, the paired key, and a short queue (up to 50 items, up to 24 hours) of notifications that could not be delivered while your Mac was unreachable. The queue is deleted once delivered or expired.
- On the Mac: the paired key and a notification history (up to 100 items) kept locally on your Mac. You can clear it in the app.

## Sharing
We do not sell, share or transfer your data to anyone.

## Your control
You can revoke Notification Access in Android settings at any time, remove apps from the forwarding list, or uninstall the app to delete all data on the phone. Deleting the Mac app's data folder removes it from the Mac.

## Children
The app is not directed at children.

## Contact
Questions: open an issue at https://github.com/GedOfGont/notifybridge/issues
