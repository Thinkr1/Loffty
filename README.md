<div align="center">

![banner](https://ghrb.waren.build/banner?header=Loffty&subheader=Your+notch%2C+truly&bg=00000000&color=FFFFFF&headerfont=Manrope&subheaderfont=Kinewave&support=false)

[![Tests](https://github.com/Thinkr1/Loffty/actions/workflows/xcode-build-test.yml/badge.svg)](https://github.com/Thinkr1/Loffty/actions/workflows/xcode-build-test.yml)
[![Latest Version](https://img.shields.io/github/v/release/Thinkr1/Loffty?label=latest%20version)](https://github.com/Thinkr1/Loffty/releases/latest)
![macOS](https://img.shields.io/badge/macOS-15%2B-black?logo=apple)
![Swift](https://img.shields.io/badge/Swift-6-orange?logo=swift)

## A Dynamic Island for your Mac.

Loffty turns your notch into a live, interactive Dynamic Island for music, system controls, AirDrop, and more.

</div>

<p align="center">
  <img width="1920" alt="Expanded Loffty" src="https://github.com/user-attachments/assets/574ef403-2415-481d-8c55-e4aeefc526a4" />
  <img width="1920" alt="Lockscreen Loffty (not expanded)" src="https://github.com/user-attachments/assets/a1bdc943-661a-4c65-9554-f45ddecebd7a" />
</p>


## Installation

Download the latest `.zip` or `.dmg` from the [latest release](../../releases/latest).

> **Beta:** Loffty is still in development.  Feedback is warmly welcome.

### First launch

Loffty is currently not notarized because it is being developed without a paid Apple Developer account.

As a result, macOS may prevent the app from opening the first time.

#### Option A — Open Anyway

1. Try to open Loffty normally.
2. Open **System Settings → Privacy & Security**.
3. Scroll down to the **Security** section.
4. Click **Open Anyway** next to Loffty.

<p align="center">
  <img width="455" alt="macOS security warning" src="https://github.com/user-attachments/assets/0e854a39-215e-4eb3-9c08-4fca3cb33e9a" />
</p>

#### Option B — Terminal

If **Open Anyway** does not appear:

```sh
sudo xattr -rd com.apple.quarantine /path/to/Loffty.app
```

Then open Loffty normally.

## Beta testing

Loffty is currently in its early stages of development. If you have a notched MacBook, feel free to try it out and let me know what you think.

Found a bug, have a suggestion, or want to see something added? [Open an issue](../../issues) or join the [Discussions](../../discussions).

## Roadmap

Some things I'm currently working on:

- Features/improvements
  - Add queue?
  - Add more controls (shuffle, repeat, etc)
  - Actual soundwaves
  - Lock screen lyrics
  - Timer, live activities
  - Support more apps for push notifications
  - Show profile picture in push notifications
  - Dual Discord/server image badges for notifications
  - Improve lock screen widget (+show music video option)
  - Show website for browser source
  - Full browser video thumb
  - 1:1 marquee speed
  - Screensaver music video
  - Auto-expand on track change?
  - media-control skip Spotify ads
  - Golden Gate update
- Fixes
  - Remove system focus HUD

## Contributing

Contributions are welcome. Feel free to [open an issue](../../issues) with a bug, feature request, or idea, or submit a pull request.

## License

Loffty is released under the [BSD-3-Clause license](LICENSE).

## Acknowledgements

Special thanks to Alcove for the original inspiration.

Loffty also includes [mediaremote-adapter](https://github.com/ungive/mediaremote-adapter) by Jonas van den Berg (ungive), bundled under `Loffty/Dependencies/MediaRemoteAdapter/`.

It is distributed under the BSD-3-Clause license. See its `LICENSE` and `NOTICE` files for details.
