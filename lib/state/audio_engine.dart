import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import 'package:audio_service/audio_service.dart';
import '../services/audio_handler.dart';

// Core Audio Engine & Handler
final audioHandlerProvider = Provider<AudioHandler>((ref) => throw UnimplementedError());

final audioPlayerProvider = Provider<AudioPlayer>((ref) {
  final handler = ref.watch(audioHandlerProvider) as ChillAudioHandler;
  return handler.player;
});

final androidEqualizerProvider = Provider<AndroidEqualizer>((ref) {
  final handler = ref.watch(audioHandlerProvider) as ChillAudioHandler;
  return handler.equalizer;
});
