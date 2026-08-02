<div align="center"
  
# Loffty

### A Dynamic Island for your Mac.

</div>

Loffty turns the notch into a live, interactive Dynamic Island for music, system controls, AirDrop, and more.

<p align="center">
  <img width="1920" alt="Expanded Loffty" src="https://github.com/user-attachments/assets/adadd8c8-2809-4b4b-8f3b-9991cae38cf4" />
</p>

<p align="center">
  <img width="1920" alt="Lockscreen Loffty" src="https://github.com/user-attachments/assets/6d920f5e-bc1e-4cb0-ba1f-92dca3f41c34" />
</p>

## Installation

Download the latest `.zip` or `.dmg` from the [latest release](../../releases/latest).

> **Beta:** Loffty is still in development.  Feedback is very welcome.

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

Loffty is currently in its early stages of development. If you have a notched MacBook, feel free try it out and let me know what you think.

Found a bug, have a suggestion, or want to see something added? [Open an issue](../../issues) or get in touch directly.

## Roadmap

Some things I'm currently working on:

- Features/improvements
  - Add queue?
  - Add more controls (shuffle, repeat, etc)
  - Actual soundwaves
  - Lock screen lyrics
  - Login item
  - AirPlay
  - Timer, live activities
  - WhatsApp, Messages, Discord (+more) notifications (+reply, show more)
  - Improve lock screen widget (+full screen artwork, show music video option)
  - Screensaver music video
  - Auto-expand on track change?
  - media-control skip Spotify ads
  - Golden Gate update
- Fixes
  - Remove system focus HUD
  - Album match geometry crosses below physical notch thereby making it visible
  - Apple Music occasional crashes

## Contributing

Contributions are welcome. Feel free to [open an issue](../../issues) with a bug, feature request, or idea, or submit a pull request.

## License

Loffty is released under the [BSD-3-Clause license](LICENSE).

## Acknowledgements

Special thanks to Alcove for the original inspiration.

Loffty also includes [mediaremote-adapter](https://github.com/ungive/mediaremote-adapter) by Jonas van den Berg (ungive), bundled under `Loffty/Dependencies/MediaRemoteAdapter/`.

It is distributed under the BSD-3-Clause license. See its `LICENSE` and `NOTICE` files for details.
