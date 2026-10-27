import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opc_app/core/app_controller.dart';
import 'package:opc_app/features/api_media_player.dart';
import 'package:video_player/video_player.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

import 'api_ui_test.dart' show LiveUiRepository, host;

class _VideoPlatform extends VideoPlayerPlatform {
  final positions = <int, Duration>{};
  int creates = 0;
  int plays = 0;
  @override
  Future<void> init() async {}
  @override
  Future<int> createWithOptions(VideoCreationOptions options) async {
    creates++;
    throw StateError('Control tests must not initialize a native decoder');
  }

  @override
  Future<void> setLooping(int playerId, bool looping) async {}
  @override
  Future<void> play(int playerId) async {
    plays++;
  }

  @override
  Future<void> pause(int playerId) async {}
  @override
  Future<void> setVolume(int playerId, double volume) async {}
  @override
  Future<void> setPlaybackSpeed(int playerId, double speed) async {}
  @override
  Future<void> seekTo(int playerId, Duration position) async {
    positions[playerId] = position;
  }

  @override
  Future<Duration> getPosition(int playerId) async =>
      positions[playerId] ?? Duration.zero;
  @override
  Widget buildViewWithOptions(VideoViewOptions options) =>
      const ColoredBox(color: Colors.black);
  @override
  Future<void> setMixWithOthers(bool mixWithOthers) async {}
  @override
  Future<void> setAllowBackgroundPlayback(bool allowBackgroundPlayback) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late VideoPlayerPlatform previous;
  late _VideoPlatform platform;
  final systemCalls = <MethodCall>[];
  setUp(() {
    previous = VideoPlayerPlatform.instance;
    platform = _VideoPlatform();
    VideoPlayerPlatform.instance = platform;
    systemCalls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) {
          systemCalls.add(call);
          return SynchronousFuture<Object?>(null);
        });
  });
  tearDown(() {
    VideoPlayerPlatform.instance = previous;
  });

  // 控件测试直接赋初始化状态；真实文件解码在 Android 普通应用另行实测。
  Future<VideoPlayerController> player() async {
    final result = VideoPlayerController.asset('test-video.mp4');
    result.value = const VideoPlayerValue(
      duration: Duration(seconds: 90),
      size: Size(1280, 720),
      isInitialized: true,
    );
    return result;
  }

  Future<void> show(
    WidgetTester tester,
    AppController app,
    VideoPlayerController video,
    ValueNotifier<MediaAccess> access, {
    bool audio = false,
  }) async {
    await tester.pumpWidget(
      host(
        app,
        Scaffold(
          body: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: ApiMediaPlayer(
                controller: video,
                name: 'private-video.mp4',
                access: access,
                audio: audio,
                onCommand: (action) async {
                  if (access.value != MediaAccess.allowed) return false;
                  await action(video);
                  return true;
                },
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'play, bounded skipping, scrubbing, mute, speed and end replay work',
    (tester) async {
      final video = await player();
      final app = AppController(LiveUiRepository());
      final access = ValueNotifier(MediaAccess.allowed);
      await show(tester, app, video, access);
      expect(find.text('00:00'), findsOneWidget);
      expect(find.text('01:30'), findsOneWidget);
      await tester.tap(find.byKey(const Key('media-forward')));
      await tester.pumpAndSettle();
      expect(video.value.position, const Duration(seconds: 10));
      await tester.tap(find.byKey(const Key('media-backward')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('media-backward')));
      await tester.pumpAndSettle();
      expect(video.value.position, Duration.zero);
      final seek = tester.getRect(find.byKey(const Key('media-seek')));
      await tester.tapAt(Offset(seek.left + seek.width * .7, seek.center.dy));
      await tester.pumpAndSettle();
      expect(video.value.position.inSeconds, inInclusiveRange(55, 70));
      await tester.tap(find.byKey(const Key('media-mute')));
      await tester.pumpAndSettle();
      expect(video.value.volume, 0);
      await tester.tap(find.byKey(const Key('media-mute')));
      await tester.pumpAndSettle();
      expect(video.value.volume, 1);
      await tester.tap(find.byKey(const Key('media-speed')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('1.5×').last);
      await tester.pumpAndSettle();
      expect(video.value.playbackSpeed, 1.5);
      await video.seekTo(video.value.duration);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('media-play')));
      await tester.pump();
      expect(video.value.position, Duration.zero);
      expect(video.value.isPlaying, true);
      await tester.tap(find.byKey(const Key('media-play')));
      await tester.pumpAndSettle();
      expect(video.value.isPlaying, false);
      await tester.pumpWidget(const SizedBox());
      await video.dispose();
      await tester.pump();
      access.dispose();
      app.dispose();
    },
  );

  testWidgets(
    'fullscreen shares position, speed and decoder and restores system UI on back',
    (tester) async {
      final video = await player();
      await video.seekTo(const Duration(seconds: 42));
      await video.setPlaybackSpeed(1.5);
      final app = AppController(LiveUiRepository());
      final access = ValueNotifier(MediaAccess.allowed);
      await show(tester, app, video, access);
      await tester.tap(find.byKey(const Key('media-fullscreen')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('media-fullscreen-page')), findsOneWidget);
      expect(video.value.position.inSeconds, 42);
      expect(video.value.playbackSpeed, 1.5);
      expect(platform.creates, 0);
      await tester.tap(find.byKey(const Key('media-fullscreen-back')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('media-fullscreen-page')), findsNothing);
      expect(video.value.position.inSeconds, 42);
      expect(
        systemCalls.any(
          (c) =>
              c.method == 'SystemChrome.setPreferredOrientations' &&
              (c.arguments as List).isEmpty,
        ),
        true,
      );
      expect(
        systemCalls.any(
          (c) =>
              c.method == 'SystemChrome.setEnabledSystemUIMode' &&
              c.arguments == 'SystemUiMode.edgeToEdge',
        ),
        true,
      );
      await tester.pumpWidget(const SizedBox());
      await video.dispose();
      access.dispose();
      app.dispose();
    },
  );

  testWidgets(
    'access checking hides fullscreen content and denial exits without stale frames',
    (tester) async {
      final video = await player();
      final app = AppController(LiveUiRepository());
      final access = ValueNotifier(MediaAccess.allowed);
      await show(tester, app, video, access);
      await tester.tap(find.byKey(const Key('media-fullscreen')));
      await tester.pumpAndSettle();
      access.value = MediaAccess.checking;
      await tester.pump();
      expect(find.text('private-video.mp4'), findsNothing);
      expect(find.byType(VideoPlayer), findsNothing);
      access.value = MediaAccess.allowed;
      await tester.pumpAndSettle();
      expect(find.byType(VideoPlayer), findsOneWidget);
      access.value = MediaAccess.denied;
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('media-fullscreen-page')), findsNothing);
      expect(find.byType(VideoPlayer), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await video.dispose();
      access.dispose();
      app.dispose();
    },
  );

  for (final language in ['zh', 'ja']) {
    for (final dark in [false, true]) {
      testWidgets(
        'media controls fit $language dark=$dark on small portrait and landscape screens',
        (tester) async {
          final video = await player();
          final access = ValueNotifier(MediaAccess.allowed);
          final app = AppController(LiveUiRepository());
          await app.setLocale(Locale(language));
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetDevicePixelRatio);
          addTearDown(tester.view.resetPhysicalSize);
          for (final size in [const Size(320, 640), const Size(640, 320)]) {
            tester.view.physicalSize = size;
            await tester.pumpWidget(
              host(
                app,
                Scaffold(
                  body: MediaQuery(
                    data: MediaQueryData(
                      size: size,
                      textScaler: const TextScaler.linear(1.5),
                    ),
                    child: SingleChildScrollView(
                      child: SizedBox(
                        width: size.width - 40,
                        child: ApiMediaPlayer(
                          controller: video,
                          name: 'video.mp4',
                          access: access,
                          onCommand: (action) async {
                            await action(video);
                            return true;
                          },
                        ),
                      ),
                    ),
                  ),
                ),
                brightness: dark ? Brightness.dark : Brightness.light,
              ),
            );
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
          }
          await tester.pumpWidget(const SizedBox());
          await video.dispose();
          access.dispose();
          app.dispose();
        },
      );
    }
  }

  testWidgets('audio retains transport controls without video fullscreen', (
    tester,
  ) async {
    final video = await player();
    final app = AppController(LiveUiRepository());
    final access = ValueNotifier(MediaAccess.allowed);
    await show(tester, app, video, access, audio: true);
    expect(find.byIcon(Icons.audiotrack), findsOneWidget);
    expect(find.byKey(const Key('media-fullscreen')), findsNothing);
    expect(find.byKey(const Key('media-seek')), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await video.dispose();
    access.dispose();
    app.dispose();
  });
}
