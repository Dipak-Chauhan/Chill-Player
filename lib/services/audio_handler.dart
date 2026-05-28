import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';

class ChillAudioHandler extends BaseAudioHandler with QueueHandler {
  final AndroidEqualizer equalizer = AndroidEqualizer();
  late final AudioPlayer _player;

  ChillAudioHandler() {
    _player = AudioPlayer(
      audioPipeline: AudioPipeline(androidAudioEffects: [equalizer]),
    );

    // Broadcast playback state changes reactively
    _player.playbackEventStream.listen(_broadcastState);

    // Sync current media item and queue
    _player.sequenceStateStream.listen(_syncSequenceState);
  }

  AudioPlayer get player => _player;

  void _broadcastState(PlaybackEvent event) {
    final playing = _player.playing;
    final queueIndex = _player.currentIndex;

    final controls = [
      MediaControl.custom(
        androidIcon: _getRepeatIcon(),
        label: 'Repeat',
        name: 'repeat',
      ),
      MediaControl.skipToPrevious,
      if (playing) MediaControl.pause else MediaControl.play,
      MediaControl.skipToNext,
    ];

    playbackState.add(PlaybackState(
      controls: controls,
      systemActions: const {
        MediaAction.seek,
        MediaAction.skipToNext,
        MediaAction.skipToPrevious,
        MediaAction.play,
        MediaAction.pause,
      },
      androidCompactActionIndices: const [1, 2, 3], // skipPrevious, play/pause, skipNext
      processingState: const {
        ProcessingState.idle: AudioProcessingState.idle,
        ProcessingState.loading: AudioProcessingState.loading,
        ProcessingState.buffering: AudioProcessingState.buffering,
        ProcessingState.ready: AudioProcessingState.ready,
        ProcessingState.completed: AudioProcessingState.completed,
      }[_player.processingState]!,
      playing: playing,
      updatePosition: _player.position,
      bufferedPosition: _player.bufferedPosition,
      speed: _player.speed,
      queueIndex: queueIndex,
      updateTime: DateTime.now(),
    ));
  }

  void _syncSequenceState(SequenceState? sequenceState) {
    if (sequenceState == null) return;

    final currentSource = sequenceState.currentSource;
    if (currentSource != null && currentSource.tag is MediaItem) {
      final item = currentSource.tag as MediaItem;
      if (mediaItem.value?.id != item.id) {
        mediaItem.add(item);
      }
    }

    final effectiveSequence = sequenceState.effectiveSequence;
    final newQueue = effectiveSequence
        .map((source) => source.tag is MediaItem ? source.tag as MediaItem : null)
        .whereType<MediaItem>()
        .toList();

    queue.add(newQueue);
  }

  String _getRepeatIcon() {
    final mode = _player.loopMode;
    switch (mode) {
      case LoopMode.off:
        return 'drawable/ic_repeat_off';
      case LoopMode.one:
        return 'drawable/ic_repeat_one';
      case LoopMode.all:
        return 'drawable/ic_repeat';
    }
  }

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> stop() => _player.stop();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> skipToNext() => _player.seekToNext();

  @override
  Future<void> skipToPrevious() => _player.seekToPrevious();

  @override
  Future<void> skipToQueueItem(int index) => _player.seek(Duration.zero, index: index);

  @override
  Future<dynamic> customAction(String name, [Map<String, dynamic>? extras]) async {
    if (name == 'repeat') {
      final currentMode = _player.loopMode;
      if (currentMode == LoopMode.off) {
        await _player.setLoopMode(LoopMode.all);
      } else if (currentMode == LoopMode.all) {
        await _player.setLoopMode(LoopMode.one);
      } else {
        await _player.setLoopMode(LoopMode.off);
      }
      // Force trigger state broadcast to immediately update notification
      _broadcastState(_player.playbackEvent);
    }
    return super.customAction(name, extras);
  }
}
