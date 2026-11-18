# PiliPlus HarmonyOS Branch

[中文](README.md) | English

This branch is currently maintained by [dev4harmony/flutter-dev](https://github.com/orgs/dev4harmony/teams/flutter-dev).

- QQ group: **1106472996**

> [!WARNING]
> This branch only ports PiliPlus to HarmonyOS.
>
> Almost all features unrelated to the HarmonyOS platform are implemented upstream.

## Issue reporting notes

- [Issue board](https://github.com/users/qinshah/projects/1)

- Please check whether a similar issue already exists, and make sure the issue is specific to the HarmonyOS version.

- This branch synchronizes with upstream and generally does not add new features or change behavior.

## Build and run

> [!TIP]
> The project's compile API level has been raised to 26.0.0. Please download the latest matching IDE and SDK from Huawei's official website to avoid build errors.

- 1. Set up the HarmonyOS Flutter 3.44.9 environment; see [HarmonyOS Flutter 3.44.9](https://gitcode.com/CPF-Flutter/flutter_flutter/tree/oh-3.44.9-dev).

- 1.5. Apply the HarmonyOS rendering patches (run once before the first build; idempotent):

  ```bash
  bash tool/apply_patches.sh                                        # macOS / Linux / git-bash
  powershell -ExecutionPolicy Bypass -File tool\apply_patches.ps1   # Windows
  ```

  See [tool/patches/README.md](tool/patches/README.md) for the patch contents and rationale. The app can still compile without these patches; only the platform views for videos/web pages will be unable to enter hardware composition.

- 2. Launch via the VS Code debug configuration or the `build_hap` task to ensure the required environment variables are written into the app.

If you encounter an error like **Package not available (the pubspec for image_picker 1.1.2 from git has version 1.0.2).**, see [this Juejin article](https://juejin.cn/post/7602936997175132212).

### Contributions to the HarmonyOS port are welcome

## Thanks

- [PiliPlus upstream](https://github.com/bggRGjQaUbCoE/PiliPlus)

- Members of [dev4harmony/flutter-dev](https://github.com/orgs/dev4harmony/teams/flutter-dev)

- [ErBW_s](https://github.com/ErBWs), who adapted media_kit for HarmonyOS

- All developers and contributors

- ......

# The following is the original upstream README

<div align="center">
    <img width="200" height="200" src="assets/images/logo/logo.png">
</div>

<div align="center">
    <h1>PiliPlus</h1>
<div align="center">

[中文](README.md) | English

![GitHub repo size](https://img.shields.io/github/repo-size/bggRGjQaUbCoE/PiliPlus)
![GitHub Repo stars](https://img.shields.io/github/stars/bggRGjQaUbCoE/PiliPlus)
![GitHub all releases](https://img.shields.io/github/downloads/bggRGjQaUbCoE/PiliPlus/total)
</div>
    <p>A third-party Bilibili client built with Flutter</p>

<img src="assets/screenshots/510shots_so.png" width="32%" alt="home" />
<img src="assets/screenshots/174shots_so.png" width="32%" alt="home" />
<img src="assets/screenshots/850shots_so.png" width="32%" alt="home" />
<br/>
<img src="assets/screenshots/main_screen.png" width="96%" alt="home" />
<br/>
</div>

<br/>

## Supported platforms

- [x] Android
- [x] iOS
- [x] Pad
- [x] Windows
- [x] Linux

[![Packaging status](https://repology.org/badge/vertical-allrepos/piliplus.svg)](https://repology.org/project/piliplus/versions)

## refactor

- [ ] gRPC [wip]
- [x] User interface
- [x] Others

## feat

- [x] Edit dynamics
- [x] DLNA casting
- [x] Offline caching/playback
- [x] Tap danmaku on mobile to hover, like, copy, or report by [@My-Responsitories](https://github.com/My-Responsitories)
- [x] Audio playback
- [x] Skip anime openings/endings
- [x] Android `loudnorm` adaptation by [@My-Responsitories](https://github.com/My-Responsitories)
- [x] Geetest and SMS login on Windows/Mac by [@My-Responsitories](https://github.com/My-Responsitories)
- [x] Capture animated GIFs from videos by [@My-Responsitories](https://github.com/My-Responsitories)
- [x] AI original audio translation
- [x] SuperChat
- [x] Watch classroom videos
- [x] Create polls
- [x] Rich-text editing, emoji display, and @ mentions in dynamics/comments
- [x] Modify message settings
- [x] Modify chat settings
- [x] Show collapsed messages
- [x] View user image/text posts
- [x] Dynamic topics
- [x] Live partitions
- [x] Share videos/anime/dynamics/articles/live rooms to messages
- [x] Create/edit/delete following groups
- [x] Remove fans
- [x] Send emoji in live danmaku
- [x] Sort favorite folders
- [x] Watch later categories: ~~`Unwatched`~~ / `Partially watched` / ~~`Watched`~~
- [x] WebDAV settings backup/restore
- [x] Save comments/dynamics
- [x] Advanced danmaku by [@My-Responsitories](https://github.com/My-Responsitories)
- [x] Cancel/pin comments
- [x] Take notes
- [x] Multi-account support by [@My-Responsitories](https://github.com/My-Responsitories)
- [x] Block shopping dynamics/comments
- [x] Interactive videos
- [x] Anti-fraud warnings for comments/dynamics
- [x] High-energy progress bar
- [x] Swipe to preview video thumbnails
- [x] Live Photo
- [x] Copy/move/sort favorite folders and watch later videos
- [x] Super resolution
- [x] Merge danmaku
- [x] Member-colored danmaku
- [x] Play all/continue/reverse playback
- [x] Cookie login
- [x] Show video segment information
- [x] Adjust subtitle size
- [x] Adjust fullscreen danmaku size
- [x] Multi-select delete for favorites/watch later
- [x] Search user dynamics
- [x] Live danmaku
- [x] Edit avatar/username/bio/gender/birthday
- [x] Create/edit/delete favorite folders
- [x] View conversations in nested comments
- [x] Locate the comment tapped in nested comments
- [x] Sort nested comments by popularity/time
- [x] Downvote comments
- [x] Send images in private messages
- [x] Coin animation
- [x] Follow/unfollow anime and update follow status
- [x] Subscribe/unsubscribe collections
- [x] SponsorBlock
- [x] Show the full video collection
- [x] Triple-action animation
- [x] Anime triple action
- [x] Comments with images
- [x] Video tags
- [x] Filtered search
- [x] Repost dynamics
- [x] Collection images
- [x] Delete/pin/recall private messages
- [x] Report users/comments/videos/dynamics
- [x] Delete/publish/pin text/image dynamics
- [x] Others

## opt

- [x] Article UI
- [x] Private message UI
- [x] Favorites panel
- [x] PiP
- [x] Video covers
- [x] Reply UI
- [x] System notifications
- [x] Comment display
- [x] Brightness adjustment
- [x] Video playback
- [x] Video staff
- [x] Prevent the bottom sheet from covering fullscreen videos
- [x] Others

## fix

- [x] Like/coin/favorite individual anime episodes
- [x] Bugs

<br/>

## Features

- [x] Recommended video list (app)
- [x] Hottest video list
- [x] Popular live streams
- [x] Anime list
- [x] Block videos from blacklisted users
- [x] Incognito mode (playback treated as logged out)
- [x] Guest mode (recommendations treated as logged out)

- [x] User-related
  - [x] View fans, following, and blocked users
  - [x] View user profiles
  - [x] Follow/unfollow users
  - [x] Offline cache
  - [x] Watch later
  - [x] Watch history
  - [x] My favorites
  - [x] In-site private messages
- [x] Dynamics-related
  - [x] View all, submissions, and anime categories
  - [x] View dynamic comments
  - [x] Reply to dynamic comments

- [x] Video playback-related
  - [x] Double-tap to seek forward/backward
  - [x] Double-tap to play/pause
  - [x] Vertically adjust brightness/volume
  - [x] Swipe up to enter fullscreen, swipe down to exit
  - [x] Horizontal gestures to seek forward/backward
  - [x] Fullscreen orientation settings
  - [x] Speed selection/long-press for 2x speed
  - [x] Hardware acceleration (device-dependent)
  - [x] Video quality selection (HD quality is locked)
  - [x] Audio quality selection (video-dependent)
  - [x] Decoder format selection (video-dependent)
  - [x] Danmaku
  - [x] Subtitles
  - [x] Resume playback
  - [x] Video aspect: fit height/fit width/fill/contain, etc.
- [x] Search-related
  - [x] Hot searches
  - [x] Search history
  - [x] Default search terms
  - [x] Video, anime, live room, and user search
  - [x] Video search sorting and duration filtering
- [x] Video detail page-related
  - [x] Episode (multi-part) switching
  - [x] Like, coin, favorite/unfavorite
  - [x] Related videos
  - [x] Comment user identity badges
  - [x] Comment (sorted) viewing and second-level comment viewing
  - [x] Reply to main and second-level comments
  - [x] Like comments
  - [x] View and save note images in comments

- [x] Settings-related
  - [x] Presets for video quality, audio quality, and decoder
  - [x] Image quality settings
  - [x] Theme mode: light/dark/follow system
  - [x] Haptic feedback (optional)
  - [x] High frame rate
  - [x] Auto fullscreen
  - [x] Landscape adaptation
- [ ] And more

<br/>

## Download

Download a build from Releases on the right, or clone the repository and build it locally.

<br/>

## Disclaimer

PiliPlus is a personal project developed for interest and intended only for learning and testing. Please delete it within 24 hours of downloading.
All APIs used were collected from official websites; this project does not provide any cracked content.
Credit to the original author: [guozhigq/pilipala](https://github.com/guozhigq/pilipala).
Credit to the upstream author: [orz12/PiliPalaX](https://github.com/orz12/PiliPalaX).
This repository makes more aggressive modifications. Thank you to the original authors for their open-source spirit.

Thank you for using PiliPlus.

<br/>

## Acknowledgements

- [bilibili-API-collect](https://github.com/SocialSisterYi/bilibili-API-collect)
- [flutter_meedu_videoplayer](https://github.com/zezo357/flutter_meedu_videoplayer)
- [media-kit](https://github.com/media-kit/media-kit)
- [dio](https://pub.dev/packages/dio)
- And others

<br/>
<br/>
<br/>

## Star History

<a href="https://star-history.dera.page/#bggRGjQaUbCoE/PiliPlus&Date">
 <picture>
   <source media="(prefers-color-scheme: dark)" srcset="https://star-history.dera.page/svg?repos=bggRGjQaUbCoE/PiliPlus&type=Date&theme=dark" />
   <source media="(prefers-color-scheme: light)" srcset="https://star-history.dera.page/svg?repos=bggRGjQaUbCoE/PiliPlus&type=Date" />
   <img alt="Star History Chart" src="https://star-history.dera.page/svg?repos=bggRGjQaUbCoE/PiliPlus&type=Date" />
 </picture>
</a>
