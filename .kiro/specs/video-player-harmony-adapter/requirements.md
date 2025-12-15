# Requirements Document

## Introduction

本文档定义了 PiliPlus 应用从 media_kit 视频播放器迁移到 video_player 的需求，以支持鸿蒙（HarmonyOS）平台。当前应用使用 media_kit 作为视频播放核心，但 media_kit 不支持鸿蒙平台，因此需要适配到支持鸿蒙的 video_player 插件。

## Glossary

- **PlPlayerController**: PiliPlus 的播放器控制器，封装了视频播放的核心逻辑
- **media_kit**: 当前使用的跨平台视频播放库，基于 MPV
- **video_player**: Flutter 官方视频播放插件，已有鸿蒙适配版本
- **VideoController**: media_kit 的视频控制器类
- **VideoPlayerController**: video_player 的视频控制器类
- **DataSource**: 视频数据源配置，包含视频URL、音频URL、HTTP头等信息
- **PlayerStatus**: 播放器状态枚举（playing, paused, completed等）

## Requirements

### Requirement 1

**User Story:** As a developer, I want to replace media_kit with video_player in PlPlayerController, so that the app can play videos on HarmonyOS.

#### Acceptance Criteria

1. WHEN the PlPlayerController initializes THEN the system SHALL create a VideoPlayerController instance instead of media_kit Player
2. WHEN a video source is set THEN the system SHALL configure VideoPlayerController with the video URL and HTTP headers
3. WHEN the player state changes THEN the system SHALL emit corresponding PlayerStatus events through the existing observable streams
4. WHEN the video position updates THEN the system SHALL update the position, sliderPosition, and buffered observables
5. WHEN the video duration is available THEN the system SHALL update the duration observable

### Requirement 2

**User Story:** As a user, I want to control video playback (play, pause, seek), so that I can watch videos normally.

#### Acceptance Criteria

1. WHEN the play method is called THEN the system SHALL start video playback via VideoPlayerController.play()
2. WHEN the pause method is called THEN the system SHALL pause video playback via VideoPlayerController.pause()
3. WHEN seekTo is called with a position THEN the system SHALL seek to that position via VideoPlayerController.seekTo()
4. WHEN setPlaybackSpeed is called THEN the system SHALL set the playback rate via VideoPlayerController.setPlaybackSpeed()

### Requirement 3

**User Story:** As a user, I want to see the video rendered on screen, so that I can watch the content.

#### Acceptance Criteria

1. WHEN the video is loaded THEN the system SHALL provide a VideoPlayer widget for rendering
2. WHEN the video aspect ratio changes THEN the system SHALL update the display accordingly
3. WHEN videoFit is changed THEN the system SHALL apply the corresponding BoxFit to the video display

### Requirement 4

**User Story:** As a user, I want to adjust volume, so that I can control the audio level.

#### Acceptance Criteria

1. WHEN setVolume is called THEN the system SHALL adjust the volume via VideoPlayerController.setVolume()
2. WHEN the volume changes THEN the system SHALL update the volume observable

### Requirement 5

**User Story:** As a developer, I want to handle video errors gracefully, so that users get appropriate feedback.

#### Acceptance Criteria

1. WHEN a video fails to load THEN the system SHALL update dataStatus to error state
2. WHEN a playback error occurs THEN the system SHALL display an error message via SmartDialog.showToast()

### Requirement 6

**User Story:** As a user, I want the player to remember my playback position, so that I can resume watching later.

#### Acceptance Criteria

1. WHEN the video position changes THEN the system SHALL call makeHeartBeat to record progress
2. WHEN initializing with a seekTo position THEN the system SHALL seek to that position after loading

### Requirement 7

**User Story:** As a developer, I want to maintain backward compatibility with non-HarmonyOS platforms, so that the app continues to work on Android/iOS.

#### Acceptance Criteria

1. WHEN running on non-HarmonyOS platforms THEN the system SHALL use the same video_player API
2. WHEN platform-specific features are unavailable THEN the system SHALL gracefully degrade functionality

### Requirement 8

**User Story:** As a user, I want looping playback to work, so that I can watch videos repeatedly.

#### Acceptance Criteria

1. WHEN looping is enabled THEN the system SHALL set VideoPlayerController.setLooping(true)
2. WHEN the video completes with looping enabled THEN the system SHALL restart playback from the beginning

### Requirement 9

**User Story:** As a developer, I want to properly dispose of resources, so that there are no memory leaks.

#### Acceptance Criteria

1. WHEN dispose is called THEN the system SHALL call VideoPlayerController.dispose()
2. WHEN dispose is called THEN the system SHALL cancel all stream subscriptions
