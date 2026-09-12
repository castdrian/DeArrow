# DeArrow

DeArrow brings community-submitted titles and thumbnails to YouTube for iOS without touching YouTube’s networking or layout engine.

[![Release](https://github.com/castdrian/DeArrow/actions/workflows/release.yml/badge.svg)](https://github.com/castdrian/DeArrow/actions/workflows/release.yml)
[![Build](https://github.com/castdrian/DeArrow/actions/workflows/build.yml/badge.svg)](https://github.com/castdrian/DeArrow/actions/workflows/build.yml)
[![License](https://img.shields.io/github/license/castdrian/DeArrow?style=flat-square)](https://github.com/castdrian/DeArrow/blob/main/LICENSE)

<p align="center"><img src="layout/Library/Application%20Support/DeArrow.bundle/dearrow.svg" alt="DeArrow" width="128"></p>

## Features

- Replaces eligible video titles with DeArrow alternatives.
- Replaces eligible thumbnails through the dedicated DeArrow thumbnail service.
- Covers feeds, search, related videos, playlists, channel listings, playback, and Shorts.
- Coalesces requests, caches positive and negative results, and cancels stale cell work.
- Provides a native YouTube settings entry with independent title and thumbnail controls.
- Supports rootless ElleKit injection and sideloaded YouTube builds.

## Compatibility

| Component | Supported baseline | Latest verified |
| --- | --- | --- |
| iOS / iPadOS | 15.0+ | 27.0 |
| YouTube | 19.42.1 | 21.36.6 |

The latest verified YouTube version is the App Store release available on September 12, 2026. The tweak leaves unsupported or unknown renderer paths untouched.

## Download

[Install from the apt repository](https://repo.adriancastro.dev) · [Download the latest release](https://github.com/castdrian/DeArrow/releases/latest)

## Installation

Install the rootless package from a compatible package manager or inject `DeArrow.dylib` into a sideloaded YouTube build. Restart YouTube after installation.

## Building

Install Theos, clone [YouTubeHeader](https://github.com/PoomSmart/YouTubeHeader) into `$THEOS/include/YouTubeHeader`, and run:

```sh
gmake package FINALPACKAGE=1
```

The package is written to `packages/`.

## Attribution

This project is a maintained fork of [pixelomer/DeArrow-iOS](https://github.com/pixelomer/DeArrow-iOS). DeArrow’s public branding data is provided by [DeArrow](https://dearrow.ajay.app/).
