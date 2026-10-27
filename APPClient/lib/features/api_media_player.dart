import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import '../l10n/strings.dart';

enum MediaAccess { checking, allowed, denied }

typedef MediaCommand =
    Future<bool> Function(
      Future<void> Function(VideoPlayerController controller) action,
    );

String mediaTime(Duration time) {
  final seconds = time.inSeconds.clamp(0, 1 << 31);
  final minutes = (seconds ~/ 60 % 60).toString().padLeft(2, '0');
  final rest = (seconds % 60).toString().padLeft(2, '0');
  return seconds >= 3600
      ? '${seconds ~/ 3600}:$minutes:$rest'
      : '$minutes:$rest';
}

/// 内嵌与全屏共享一个播放器；进入全屏不重新下载或创建第二个解码器。
class ApiMediaPlayer extends StatefulWidget {
  const ApiMediaPlayer({
    super.key,
    required this.controller,
    required this.name,
    required this.access,
    required this.onCommand,
    this.audio = false,
  });
  final VideoPlayerController controller;
  final String name;
  final ValueNotifier<MediaAccess> access;
  final MediaCommand onCommand;
  final bool audio;

  @override
  State<ApiMediaPlayer> createState() => _ApiMediaPlayerState();
}

class _ApiMediaPlayerState extends State<ApiMediaPlayer> {
  bool _fullscreen = false;

  Future<void> _openFullscreen() async {
    if (_fullscreen || widget.access.value != MediaAccess.allowed) return;
    _fullscreen = true;
    try {
      if (!await widget.onCommand((_) async {}) || !mounted) return;
      // 应用其余页面未锁方向；退出全屏恢复系统方向策略与边到边模式。
      try {
        await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
        if (widget.controller.value.aspectRatio > 1) {
          await SystemChrome.setPreferredOrientations([
            DeviceOrientation.landscapeLeft,
            DeviceOrientation.landscapeRight,
          ]);
        }
      } on PlatformException catch (_) {
        // 平板／系统限制方向或系统栏时仍可使用全屏页面。
      }
      if (!mounted || widget.access.value != MediaAccess.allowed) return;
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => _FullscreenMedia(
            controller: widget.controller,
            name: widget.name,
            access: widget.access,
            onCommand: widget.onCommand,
          ),
        ),
      );
    } finally {
      _fullscreen = false;
      try {
        await SystemChrome.setPreferredOrientations([]);
        await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      } on PlatformException catch (_) {
        // 系统拒绝 UI 模式切换时，不影响返回原文件页面。
      }
    }
  }

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(16),
    child: _MediaView(
      controller: widget.controller,
      access: widget.access,
      onCommand: widget.onCommand,
      audio: widget.audio,
      onFullscreen: widget.audio ? null : _openFullscreen,
    ),
  );
}

class _FullscreenMedia extends StatefulWidget {
  const _FullscreenMedia({
    required this.controller,
    required this.name,
    required this.access,
    required this.onCommand,
  });
  final VideoPlayerController controller;
  final String name;
  final ValueNotifier<MediaAccess> access;
  final MediaCommand onCommand;
  @override
  State<_FullscreenMedia> createState() => _FullscreenMediaState();
}

class _FullscreenMediaState extends State<_FullscreenMedia> {
  @override
  void initState() {
    super.initState();
    widget.access.addListener(_accessChanged);
  }

  void _accessChanged() {
    if (widget.access.value != MediaAccess.denied) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && ModalRoute.of(context)?.isCurrent == true) {
        Navigator.pop(context);
      }
    });
  }

  @override
  void dispose() {
    widget.access.removeListener(_accessChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    key: const Key('media-fullscreen-page'),
    backgroundColor: Colors.black,
    body: SafeArea(
      child: ValueListenableBuilder<MediaAccess>(
        valueListenable: widget.access,
        builder: (context, access, _) {
          final s = l10n(context);
          return Column(
            children: [
              Row(
                children: [
                  IconButton(
                    key: const Key('media-fullscreen-back'),
                    tooltip: s.mediaExitFullscreen,
                    color: Colors.white,
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.arrow_back),
                  ),
                  if (access == MediaAccess.allowed)
                    Expanded(
                      child: Text(
                        widget.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                ],
              ),
              Expanded(
                child: access == MediaAccess.allowed
                    ? _MediaView(
                        controller: widget.controller,
                        access: widget.access,
                        onCommand: widget.onCommand,
                        fullscreen: true,
                        onFullscreen: () => Navigator.pop(context),
                      )
                    : Center(
                        child: access == MediaAccess.checking
                            ? const CircularProgressIndicator()
                            : Text(
                                s.apiFileUnavailable,
                                style: const TextStyle(color: Colors.white),
                              ),
                      ),
              ),
            ],
          );
        },
      ),
    ),
  );
}

class _MediaView extends StatelessWidget {
  const _MediaView({
    required this.controller,
    required this.access,
    required this.onCommand,
    this.audio = false,
    this.fullscreen = false,
    this.onFullscreen,
  });
  final VideoPlayerController controller;
  final ValueNotifier<MediaAccess> access;
  final MediaCommand onCommand;
  final bool audio;
  final bool fullscreen;
  final VoidCallback? onFullscreen;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<MediaAccess>(
    valueListenable: access,
    builder: (context, state, _) => state == MediaAccess.allowed
        ? _player(context)
        : ColoredBox(
            color: const Color(0xFF102025),
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Center(
                child: state == MediaAccess.checking
                    ? const CircularProgressIndicator()
                    : Text(
                        l10n(context).apiFileUnavailable,
                        style: const TextStyle(color: Colors.white),
                      ),
              ),
            ),
          ),
  );

  Widget _player(BuildContext context) => ColoredBox(
    color: const Color(0xFF102025),
    child: ValueListenableBuilder<VideoPlayerValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        if (value.hasError) {
          return Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              l10n(context).filePreviewFailed,
              style: const TextStyle(color: Colors.white),
            ),
          );
        }
        final screen = Stack(
          alignment: Alignment.center,
          children: [
            if (audio)
              const SizedBox(
                height: 116,
                width: double.infinity,
                child: Icon(Icons.audiotrack, color: Colors.white70, size: 56),
              )
            else
              AspectRatio(
                aspectRatio: value.aspectRatio > 0 ? value.aspectRatio : 16 / 9,
                child: VideoPlayer(controller),
              ),
            if (value.isBuffering)
              const CircularProgressIndicator(color: Colors.white),
          ],
        );
        return Column(
          mainAxisSize: fullscreen ? MainAxisSize.max : MainAxisSize.min,
          children: [
            if (fullscreen) Expanded(child: Center(child: screen)) else screen,
            _MediaControls(
              controller: controller,
              access: access,
              onCommand: onCommand,
              onFullscreen: onFullscreen,
              fullscreen: fullscreen,
            ),
          ],
        );
      },
    ),
  );
}

class _MediaControls extends StatefulWidget {
  const _MediaControls({
    required this.controller,
    required this.access,
    required this.onCommand,
    required this.fullscreen,
    this.onFullscreen,
  });
  final VideoPlayerController controller;
  final ValueNotifier<MediaAccess> access;
  final MediaCommand onCommand;
  final bool fullscreen;
  final VoidCallback? onFullscreen;
  @override
  State<_MediaControls> createState() => _MediaControlsState();
}

class _MediaControlsState extends State<_MediaControls> {
  bool _acting = false;
  double? _seeking;
  double _volumeBeforeMute = 1;

  Future<void> _run(
    Future<void> Function(VideoPlayerController) command,
  ) async {
    if (_acting || widget.access.value != MediaAccess.allowed) return;
    setState(() => _acting = true);
    try {
      await widget.onCommand(command);
    } finally {
      if (mounted) setState(() => _acting = false);
    }
  }

  Future<void> _skip(int seconds) => _run(
    (c) => c.seekTo(
      Duration(
        milliseconds: (c.value.position.inMilliseconds + seconds * 1000).clamp(
          0,
          c.value.duration.inMilliseconds,
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final value = widget.controller.value;
    final s = l10n(context);
    final duration = value.duration.inMilliseconds;
    final position = (_seeking ?? value.position.inMilliseconds.toDouble())
        .clamp(0, duration)
        .toDouble();
    final enabled =
        !_acting &&
        widget.access.value == MediaAccess.allowed &&
        !value.hasError;
    final ended = duration > 0 && value.position >= value.duration;
    final play = [
      IconButton(
        key: const Key('media-backward'),
        tooltip: s.mediaBackward,
        color: Colors.white,
        onPressed: enabled ? () => _skip(-10) : null,
        icon: const Icon(Icons.replay_10),
      ),
      IconButton.filled(
        key: const Key('media-play'),
        tooltip: value.isPlaying
            ? s.mediaPause
            : ended
            ? s.mediaReplay
            : s.apiPlay,
        style: IconButton.styleFrom(
          backgroundColor: const Color(0xFF087F70),
          foregroundColor: Colors.white,
        ),
        onPressed: enabled
            ? () => _run((c) async {
                if (c.value.isPlaying) {
                  await c.pause();
                } else {
                  if (ended) await c.seekTo(Duration.zero);
                  if (widget.access.value == MediaAccess.allowed) {
                    await c.play();
                  }
                }
              })
            : null,
        icon: Icon(
          value.isPlaying
              ? Icons.pause_circle_outline
              : ended
              ? Icons.replay
              : Icons.play_circle_outline,
        ),
      ),
      IconButton(
        key: const Key('media-forward'),
        tooltip: s.mediaForward,
        color: Colors.white,
        onPressed: enabled ? () => _skip(10) : null,
        icon: const Icon(Icons.forward_10),
      ),
    ];
    final tools = [
      IconButton(
        key: const Key('media-mute'),
        tooltip: value.volume == 0 ? s.mediaUnmute : s.mediaMute,
        color: Colors.white,
        onPressed: enabled
            ? () => _run((c) async {
                if (c.value.volume > 0) {
                  _volumeBeforeMute = c.value.volume;
                  await c.setVolume(0);
                } else {
                  await c.setVolume(_volumeBeforeMute);
                }
              })
            : null,
        icon: Icon(
          value.volume == 0
              ? Icons.volume_off_outlined
              : Icons.volume_up_outlined,
        ),
      ),
      PopupMenuButton<double>(
        key: const Key('media-speed'),
        tooltip: s.mediaSpeed,
        enabled: enabled,
        initialValue: value.playbackSpeed,
        onSelected: (speed) => _run((c) => c.setPlaybackSpeed(speed)),
        itemBuilder: (_) => [
          for (final speed in [.5, 1.0, 1.25, 1.5, 2.0])
            PopupMenuItem(
              value: speed,
              child: Text(
                '${speed == speed.roundToDouble() ? speed.toInt() : speed}×',
              ),
            ),
        ],
        child: SizedBox(
          width: 48,
          height: 48,
          child: Center(
            child: Text(
              '${value.playbackSpeed == value.playbackSpeed.roundToDouble() ? value.playbackSpeed.toInt() : value.playbackSpeed}×',
              style: const TextStyle(color: Colors.white, fontSize: 13),
            ),
          ),
        ),
      ),
      if (widget.onFullscreen != null)
        IconButton(
          key: const Key('media-fullscreen'),
          tooltip: widget.fullscreen
              ? s.mediaExitFullscreen
              : s.mediaFullscreen,
          color: Colors.white,
          onPressed: enabled ? widget.onFullscreen : null,
          icon: Icon(
            widget.fullscreen ? Icons.fullscreen_exit : Icons.fullscreen,
          ),
        ),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  mediaTime(Duration(milliseconds: position.round())),
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
              ),
              Text(
                mediaTime(value.duration),
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 3,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
            ),
            child: Slider(
              key: const Key('media-seek'),
              value: position,
              max: duration > 0 ? duration.toDouble() : 1,
              activeColor: const Color(0xFF64DDB4),
              inactiveColor: Colors.white24,
              semanticFormatterCallback: (ms) =>
                  mediaTime(Duration(milliseconds: ms.round())),
              onChanged: enabled && duration > 0
                  ? (value) => setState(() => _seeking = value)
                  : null,
              onChangeEnd: enabled && duration > 0
                  ? (value) async {
                      await _run(
                        (c) => c.seekTo(Duration(milliseconds: value.round())),
                      );
                      if (mounted) setState(() => _seeking = null);
                    }
                  : null,
            ),
          ),
          LayoutBuilder(
            builder: (context, constraints) => constraints.maxWidth < 288
                ? Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: play,
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: tools,
                      ),
                    ],
                  )
                : Row(children: [...play, const Spacer(), ...tools]),
          ),
        ],
      ),
    );
  }
}
