# DeArrow

[![Release](https://github.com/castdrian/DeArrow/actions/workflows/release.yml/badge.svg)](https://github.com/castdrian/DeArrow/actions/workflows/release.yml)
[![Build](https://github.com/castdrian/DeArrow/actions/workflows/build.yml/badge.svg)](https://github.com/castdrian/DeArrow/actions/workflows/build.yml)
[![Crowdin](https://img.shields.io/badge/Crowdin-Translations-2ab27b?logo=crowdin&logoColor=white)](https://crowdin.com/project/dearrow)

YouTube tweak that brings community-submitted titles and thumbnails to YouTube for iOS.

<p align="center"><img src="layout/Library/Application%20Support/DeArrow.bundle/dearrow.svg" alt="DeArrow" width="128"></p>

## Download

<p>
  <a href="https://repo.adriancastro.dev"><img src="assets/apt-repo-badge.svg" alt="Add DeArrow to your package manager" height="60"></a>
  &nbsp;
  <a href="https://github.com/castdrian/DeArrow/releases/latest"><img src="assets/github-release-badge.svg" alt="Download the latest DeArrow release" height="60"></a>
</p>

## Features

- Replace eligible titles with community-submitted DeArrow alternatives
- Replace eligible thumbnails through the dedicated DeArrow thumbnail service
- Apply branding across feeds, search, related videos, playlists, channel listings, playback, and Shorts
- Preserve YouTube branding when a response is unavailable, invalid, or stale
- Configure title and thumbnail behavior from a native YouTube settings page
- Support rootless ElleKit packages and sideloaded YouTube injection

## Compatibility

![DeArrow compatibility](.github/compatibility.svg)

## Installation

Install the rootless package from a compatible package manager, or inject `DeArrow.dylib` into a sideloaded YouTube build. Restart YouTube after installation.

## Building

Install Theos, clone [YouTubeHeader](https://github.com/PoomSmart/YouTubeHeader) into `$THEOS/include/YouTubeHeader`, and run:

```sh
gmake package FINALPACKAGE=1
```

The package is written to `packages/`.

## Testing

Run the deterministic fixture and architecture checks with:

```sh
gmake test
gmake verify-architecture
go run ./scripts/branding-smoke
```

The read-only SE diagnostic harness records package versions, process state, crash reports, and a screenshot without changing app data:

```sh
go run ./scripts/dearrow-tools device-debug 00008030-001624583AF9402E ./test-artifacts/device-debug
```

For simulator work, set `DEARROW_SIMULATOR_ID` and optionally `DEARROW_SIMULATOR_DYLIB`, `DEARROW_CYDIASUBSTRATE`, `DEARROW_SIMSLIM_BIN`, and `DEARROW_SIMFORGE_BIN`, then run `go run ./scripts/dearrow-tools simulator-debug`. The settings loop is available as `simulator-settings-regression`; it writes all screenshots, OCR, logs, and memory artifacts to `test-artifacts/`. To use a sideloaded app without replacing an already-installed signed-in copy, run `go run ./scripts/dearrow-tools simulator-sideload-debug SIMULATOR APP_PATH`.


## Privacy and network behavior

DeArrow does not intercept YouTube networking or collect telemetry. It contacts the public DeArrow and SponsorBlock branding services by video ID, caches successful and negative responses, and silently keeps YouTube’s original title or thumbnail when a request fails.

## Attribution

This project is a maintained fork of [pixelomer/DeArrow-iOS](https://github.com/pixelomer/DeArrow-iOS). Community branding data is provided by [DeArrow](https://dearrow.ajay.app/) and [SponsorBlock](https://sponsor.ajay.app/).

## Contributors

[![Contributors](https://contrib.rocks/image?repo=castdrian/DeArrow)](https://github.com/castdrian/DeArrow/graphs/contributors)
