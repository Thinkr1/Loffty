# MediaRemote Adapter (bundled)

Loffty ships a copy of [ungive/mediaremote-adapter](https://github.com/ungive/mediaremote-adapter)
so users do not need Homebrew `media-control`.

## Contents

- `mediaremote-adapter.pl` — entry script (run via `/usr/bin/perl`)
- `MediaRemoteAdapter.framework` — helper framework (copied into the app, not linked)
- `MediaRemoteAdapterTestClient` — helper for the upstream `test` command
- `LICENSE` — upstream BSD 3-Clause license
- `NOTICE` — pinned version / attribution

## How Loffty invokes it

```sh
/usr/bin/perl \
  /path/to/mediaremote-adapter.pl \
  /path/to/MediaRemoteAdapter.framework \
  stream
