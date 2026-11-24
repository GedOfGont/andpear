# NotifyBridge

See your Android notifications on your Mac. Private, end-to-end encrypted, no account, no cloud.

- Native macOS banners with the app icon, inline reply, copy code / link buttons
- Dismiss on one device, it clears on the other
- Missed notifications are delivered when the Mac is back online
- Share text from the phone to the Mac clipboard, "find my phone", pause, history

## Install

**Mac** (macOS 13+):

```
brew install --cask GedOfGont/notifybridge/notifybridge
```

**Android**: install NotifyBridge from Google Play (link coming soon), open it, scan the QR code shown by the Mac app and allow notification access. Both devices must be on the same Wi-Fi network.

## How it works

The phone finds the Mac through Bonjour (`_notifybridge._tcp`) and sends length-prefixed frames over TCP. Each frame is encrypted with AES-256-GCM using a 256-bit key that is created on the Mac and handed to the phone through the pairing QR code. There is no server; see [PRIVACY.md](PRIVACY.md).

## Build

- Mac: `cd mac && ./bundle.sh` (Swift 5 toolchain, Xcode command line tools; `./package.sh` makes the zip)
- Android: `cd android && ./gradlew :app:assembleDebug`

## License

MIT, see [LICENSE](LICENSE).
