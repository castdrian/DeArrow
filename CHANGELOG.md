# Changelog

## 1.0.0 - 2026-09-25

### Features

- complete DeArrow v1 integration (e7b9db7)
- support safe simulator sideload diagnostics (62b0a08)
- add device and simulator diagnostics (14e37a2)
- complete DeArrow branding and settings integration (af923ae)
- polish native DeArrow settings (d0a81af)
- add native settings and source layout (d0efb96)
- rebuild DeArrow integration (1b55e1e)

### Fixes

- stabilize live branding integration (dd873a4)
- avoid unsafe title setter hooks (d7e5321)
- remove unsafe player ancestry lookup (9402065)
- validate player hook signatures (d8c58a7)
- align about section with Gonerino (288d073)
- remove recursive feed branding work (4bcd195)
- install clang-format for validation (9de00b6)
- validate credentials before external syncs (4cb917a)
- remove legacy navigation fallbacks (ce1c73a)
- permit automated release dispatch (4e02498)
- use built-in token for Crowdin workflows (bb9d743)
- render DeArrow mark in settings row (878f2f7)
- make standalone settings compile on CI (69b1599)
- harden standalone navigation (8ff063a)
- support standalone settings navigation (d6cfe52)
- limit hooks to supported YouTube classes (f3fd613)
- stabilize shared tweak settings integration (ce980a5)
- remove standalone category after shared host (a2bcd9f)
- preserve branded DeArrow row icon (d7f56ca)
- cover all image node variants (6d139f2)
- use branded row icon (595dcd0)
- persist generated release changelog (3444fd3)
- declare Crowdin configuration inputs (508ac07)
- cover wrapped titles and player transitions (5215ae8)
- re-register after shared host load (e944bba)
- preserve shared DeArrow icon rendering (78e2268)
- support standalone navigation (ee426f4)
- harden branding lifecycle and player titles (c33b4f9)
- share headerless tweak category (b3941cc)
- restore DeArrow settings registration (6515013)
- stabilize settings and branding integration (711a28d)
- guard thumbnail URL containers (e79c05a)
- harden runtime hooks and metadata requests (090deb6)
- reset branding state on node reuse (420a79e)
- clean settings action callback (f16760d)
- make changelog generation repeatable (a27e2f1)
- refresh thumbnails when preferences change (979d2b5)
- stabilize branding and settings integration (ee1b814)
- avoid Theos package version collision (2f5f389)

### Performance

- avoid synchronous branding cache reads (e46dfe5)
- avoid repeated player metadata parsing (216bde0)
- reuse normalized video metadata (a44a902)

### Documentation

- remove internal simulator diagnostics (a58ca8e)
- update verified YouTube compatibility (3d92690)
- align compatibility matrix with verified environment (6697a78)
- record current compatibility target (ecf7f34)
- refresh changelog data (b8bb825)
- refresh changelog data (aaee0a0)
- align DeArrow project presentation (8794956)
- align DeArrow project presentation (f230e0a)
- document DeArrow compatibility and usage (4a9ac3f)

### Tests

- add real DeArrow branding videos (df34150)
- cover branding response contracts (fefceb0)

### Build

- discover tweak sources automatically (bb0a326)
- keep package builds reproducible (a302736)

### CI

- run consolidated validation in workflows (564e272)
- track Crowdin configuration (a160b59)
- automate Crowdin translation releases (69c5252)
- automate validation and package releases (e920182)

### Maintenance

- add consolidated validation checks (eeadf07)
- ignore diagnostic artifacts (1c100ff)
- add LICENSE (7cecc47)

### Style

- format Objective-C sources (000b88a)

### Other changes

- Initial commit (2cceebf)
