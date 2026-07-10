// Barrel file for the audio/playback state layer.
// The providers were split out of this single 880-line file into focused
// modules. This barrel re-exports them so existing imports of
// `state/audio_state.dart` keep working unchanged:
//   - audio_engine.dart      core just_audio engine + handler + equalizer
//   - library_providers.dart device library list + sort options
//   - queue_provider.dart    queue, shuffle, and the playback "firewall"
//   - playback_status.dart   current song / playing / position / loop / UI flags
export 'audio_engine.dart';
export 'library_providers.dart';
export 'queue_provider.dart';
export 'playback_status.dart';
