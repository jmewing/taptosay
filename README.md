# TapToSay 🌻

Tap-to-speak AAC app: tap a tile, it says the word.

Built for Jaxon (nonverbal, ~5 y.o.) — Android first, then Apple. The mechanic comes from a classroom video: tap → instant speech.

## Status (2026-09-15)

- [x] Project name locked, private repo `jmewing/taptosay`
- [x] Android-first decision (sideload APK + Screen-Pin kiosk; no Apple fee yet)
- [x] Flutter scaffold + TTS enabled (flutter_tts)
- [x] v1 grid: 16 tap-to-speak tiles (Mom, Dad, Eat, Drink, Play, More, Stop, Help, Yes, No, Happy, Sad, Hurt, Bath, Sleep, All Done)
- [ ] Test APK on BLU M10L (in progress: toolchain on automation server, tablet factory-reset)
- [ ] Category grids (food, people, feelings, play, places)
- [ ] Picture support (user photo → tile)
- [ ] Kiosk/device-owner lock: boot straight into TapToSay
- [ ] Ship to Play Store; then App Store
- [ ] Teacher edition: multi-tablet grid sync (15 students now, 15 next year)

## Dev setup (automation server)

```bash
source ~/android-toolchain/env.sh   # flutter + adb + java on PATH
cd /srv/taptosay
flutter run                          # hot-reload dev
flutter build apk --debug             # sideload APK
adb install -r build/app/outputs/flutter-apk/app-debug.apk
```

## Privacy

No kid names in code, commits, or public surfaces. Code lives in this private repo only. Pictures of people stay on-device unless the user explicitly opts into cloud sync.

## License

MIT — see LICENSE.
