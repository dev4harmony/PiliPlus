# Design Document: Video Player Harmony Adapter

## Overview

本设计文档描述了将 PiliPlus 应用的视频播放器从 `media_kit` 迁移到 `video_player` 的技术方案，以支持鸿蒙（HarmonyOS）平台。

### 核心变更

1. **播放器核心替换**: 将 `media_kit` 的 `Player` 类替换为 `video_player` 的 `VideoPlayerController`
2. **视频渲染替换**: 将 `media_kit_video` 的 `Video`/`SimpleVideo` 组件替换为 `video_player` 的 `VideoPlayer` 组件
3. **API 适配**: 适配播放控制、状态监听、音量控制等 API 差异

### 主要差异对比

| 功能 | media_kit | video_player |
|------|-----------|--------------|
| 播放器类 | `Player` | `VideoPlayerController` |
| 视频控制器 | `VideoController` | 内置于 `VideoPlayerController` |
| 视频组件 | `Video`/`SimpleVideo` | `VideoPlayer` |
| 状态监听 | Stream-based (`player.stream.xxx`) | `addListener` + `value` |
| 播放速度 | `setRate(double)` | `setPlaybackSpeed(double)` |
| 音量控制 | `setVolume(double)` (0-100) | `setVolume(double)` (0.0-1.0) |
| 循环播放 | `setPlaylistMode(PlaylistMode)` | `setLooping(bool)` |
| 字幕 | 内置 `SubtitleView` | 需自行实现 |
| 音轨 | 支持外部音轨 | 不支持 |

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                      PlPlayerController                      │
│  ┌─────────────────────────────────────────────────────┐   │
│  │                  Public Interface                     │   │
│  │  - play(), pause(), seekTo(), setPlaybackSpeed()     │   │
│  │  - position, duration, buffered (Rx observables)     │   │
│  │  - playerStatus, dataStatus                          │   │
│  └─────────────────────────────────────────────────────┘   │
│                            │                                 │
│                            ▼                                 │
│  ┌─────────────────────────────────────────────────────┐   │
│  │              VideoPlayerController                    │   │
│  │              (from video_player)                      │   │
│  │  - initialize(), play(), pause(), seekTo()           │   │
│  │  - value.position, value.duration, value.isPlaying   │   │
│  └─────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│                      PLVideoPlayer                           │
│  ┌─────────────────────────────────────────────────────┐   │
│  │                   VideoPlayer                         │   │
│  │              (from video_player)                      │   │
│  └─────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

## Components and Interfaces

### 1. PlPlayerController 适配

#### 1.1 成员变量变更

```dart
// 移除
Player? _videoPlayerController;
VideoController? _videoController;

// 替换为
VideoPlayerController? _videoPlayerController;
```

#### 1.2 初始化方法变更

```dart
// 原 media_kit 方式
Player player = Player(configuration: PlayerConfiguration(...));
_videoController = VideoController(player, configuration: ...);

// 新 video_player 方式
_videoPlayerController = VideoPlayerController.networkUrl(
  Uri.parse(videoUrl),
  httpHeaders: httpHeaders,
);
await _videoPlayerController!.initialize();
```

#### 1.3 状态监听适配

```dart
// 原 media_kit 方式 (Stream-based)
controllerStream.playing.listen((event) { ... });
controllerStream.position.listen((event) { ... });
controllerStream.duration.listen((event) { ... });
controllerStream.buffer.listen((event) { ... });

// 新 video_player 方式 (Listener-based)
_videoPlayerController!.addListener(_onVideoPlayerUpdate);

void _onVideoPlayerUpdate() {
  final value = _videoPlayerController!.value;
  
  // 更新播放状态
  if (value.isPlaying) {
    playerStatus.value = PlayerStatus.playing;
  } else if (value.isCompleted) {
    playerStatus.value = PlayerStatus.completed;
  } else {
    playerStatus.value = PlayerStatus.paused;
  }
  
  // 更新位置
  position.value = value.position;
  
  // 更新时长
  duration.value = value.duration;
  
  // 更新缓冲
  if (value.buffered.isNotEmpty) {
    buffered.value = value.buffered.last.end;
  }
  
  // 更新缓冲状态
  isBuffering.value = value.isBuffering;
}
```

### 2. 播放控制方法适配

#### 2.1 播放/暂停

```dart
// play
Future<void> play() async {
  await _videoPlayerController?.play();
  playerStatus.value = PlayerStatus.playing;
}

// pause
Future<void> pause() async {
  await _videoPlayerController?.pause();
  playerStatus.value = PlayerStatus.paused;
}
```

#### 2.2 跳转

```dart
Future<void> seekTo(Duration position) async {
  await _videoPlayerController?.seekTo(position);
  this.position.value = position;
}
```

#### 2.3 播放速度

```dart
Future<void> setPlaybackSpeed(double speed) async {
  await _videoPlayerController?.setPlaybackSpeed(speed);
  _playbackSpeed.value = speed;
}
```

#### 2.4 音量控制

```dart
Future<void> setVolume(double volume) async {
  // video_player 音量范围是 0.0-1.0
  await _videoPlayerController?.setVolume(volume);
  this.volume.value = volume;
}
```

#### 2.5 循环播放

```dart
Future<void> setLooping(bool looping) async {
  await _videoPlayerController?.setLooping(looping);
}
```

### 3. 视频渲染组件适配

#### 3.1 PLVideoPlayer 中的视频组件

```dart
// 原 media_kit 方式
SimpleVideo(
  controller: plPlayerController.videoController!,
  fill: widget.fill,
  aspectRatio: videoFit.aspectRatio,
)

// 新 video_player 方式
AspectRatio(
  aspectRatio: _videoPlayerController!.value.aspectRatio,
  child: VideoPlayer(_videoPlayerController!),
)
```

### 4. 功能降级处理

由于 `video_player` 不支持某些 `media_kit` 的高级功能，需要进行降级处理：

#### 4.1 外部音轨 (不支持)
- `video_player` 不支持加载外部音轨
- 需要使用合并了音视频的视频源，或者放弃分离音视频的功能

#### 4.2 字幕 (需自行实现)
- `media_kit_video` 内置 `SubtitleView`
- `video_player` 需要自行实现字幕渲染

#### 4.3 超分辨率/Shader (不支持)
- `media_kit` 支持 MPV 的 GLSL shader
- `video_player` 不支持此功能

#### 4.4 硬件解码配置 (平台自动处理)
- `video_player` 由平台自动处理硬件解码

## Data Models

### VideoPlayerValue (video_player 内置)

```dart
class VideoPlayerValue {
  final Duration duration;
  final Duration position;
  final List<DurationRange> buffered;
  final bool isPlaying;
  final bool isLooping;
  final bool isBuffering;
  final double volume;
  final double playbackSpeed;
  final int? errorDescription;
  final Size size;
  final bool isInitialized;
  final bool isCompleted;
  final double aspectRatio;
}
```

### 现有模型保持不变

- `DataSource` - 视频数据源
- `PlayerStatus` - 播放状态枚举
- `DataStatus` - 数据加载状态
- `VideoFitType` - 视频适配类型

## Correctness Properties

*A property is a characteristic or behavior that should hold true across all valid executions of a system-essentially, a formal statement about what the system should do. Properties serve as the bridge between human-readable specifications and machine-verifiable correctness guarantees.*

基于 prework 分析，以下是可测试的正确性属性：

### Property 1: Video source configuration consistency
*For any* valid video URL and HTTP headers, when setDataSource is called, the VideoPlayerController SHALL be configured with the exact same URL and headers.
**Validates: Requirements 1.2**

### Property 2: Player state synchronization
*For any* player state change (playing, paused, completed), the playerStatus observable SHALL emit the corresponding PlayerStatus value.
**Validates: Requirements 1.3**

### Property 3: Position observable consistency
*For any* position update from VideoPlayerController, the position, sliderPosition observables SHALL be updated to reflect the new position value.
**Validates: Requirements 1.4**

### Property 4: Seek position delegation
*For any* valid position within video duration, calling seekTo(position) SHALL result in VideoPlayerController.seekTo being called with the same position.
**Validates: Requirements 2.3**

### Property 5: Playback speed delegation
*For any* valid playback speed value, calling setPlaybackSpeed(speed) SHALL result in VideoPlayerController.setPlaybackSpeed being called with the same speed value.
**Validates: Requirements 2.4**

### Property 6: VideoFit to BoxFit mapping
*For any* VideoFitType value, the corresponding BoxFit SHALL be correctly applied to the video display widget.
**Validates: Requirements 3.3**

### Property 7: Volume delegation
*For any* valid volume value (0.0-1.0), calling setVolume(volume) SHALL result in VideoPlayerController.setVolume being called with the same value.
**Validates: Requirements 4.1**

### Property 8: Volume observable synchronization
*For any* volume change, the volume observable SHALL be updated to reflect the new volume value.
**Validates: Requirements 4.2**

### Property 9: Initial seek position
*For any* valid initial seekTo position, after video initialization, the player SHALL seek to that position.
**Validates: Requirements 6.2**

## Error Handling

### 初始化错误

```dart
try {
  await _videoPlayerController!.initialize();
  dataStatus.status.value = DataStatus.loaded;
} catch (e) {
  dataStatus.status.value = DataStatus.error;
  SmartDialog.showToast('视频加载失败: $e');
}
```

### 播放错误

```dart
void _onVideoPlayerUpdate() {
  final value = _videoPlayerController!.value;
  if (value.hasError) {
    SmartDialog.showToast('播放错误: ${value.errorDescription}');
    dataStatus.status.value = DataStatus.error;
  }
}
```

## Testing Strategy

### 单元测试

由于这是一个适配层的改动，主要测试点包括：

1. **状态映射测试**: 验证 VideoPlayerValue 状态正确映射到 PlayerStatus
2. **方法委托测试**: 验证 play/pause/seekTo 等方法正确委托到 VideoPlayerController
3. **Observable 更新测试**: 验证位置、时长、缓冲等 observable 正确更新

### 属性测试

使用 Dart 的 `test` 包进行属性测试：

```dart
// 示例：测试 VideoFitType 到 BoxFit 的映射
test('VideoFitType maps to correct BoxFit', () {
  for (final fitType in VideoFitType.values) {
    final boxFit = fitType.boxFit;
    expect(boxFit, isNotNull);
  }
});
```

### 集成测试

由于涉及平台原生代码，需要在真机上进行集成测试：

1. 视频播放功能测试
2. 播放控制测试（播放、暂停、跳转）
3. 全屏切换测试
4. 错误处理测试

### 测试框架

- 单元测试: `flutter_test`
- 属性测试: `test` 包 (Dart 内置)
- 集成测试: `integration_test`
