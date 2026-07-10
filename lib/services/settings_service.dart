import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Provider to hold the SharedPreferences instance
final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError(
    'sharedPreferencesProvider must be overridden in main.dart',
  );
});

// A generic Notifier for SharedPreferences preferences
class PrefNotifier<T> extends Notifier<T> {
  final String prefKey;
  final T defaultValue;

  PrefNotifier(this.prefKey, this.defaultValue);

  @override
  T build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    return _load(prefs, prefKey, defaultValue);
  }

  static T _load<T>(SharedPreferences prefs, String prefKey, T defaultValue) {
    if (T == bool) {
      return (prefs.getBool(prefKey) ?? defaultValue) as T;
    } else if (T == String) {
      return (prefs.getString(prefKey) ?? defaultValue) as T;
    } else if (T == int) {
      return (prefs.getInt(prefKey) ?? defaultValue) as T;
    }
    return defaultValue;
  }

  void update(T value) {
    state = value;
    final prefs = ref.read(sharedPreferencesProvider);
    if (T == bool) {
      prefs.setBool(prefKey, value as bool);
    } else if (T == String) {
      prefs.setString(prefKey, value as String);
    } else if (T == int) {
      prefs.setInt(prefKey, value as int);
    }
  }
}

// Global settings providers
final themeModeProvider = NotifierProvider<PrefNotifier<String>, String>(() {
  return PrefNotifier<String>('theme_mode', 'system');
});

final amoledModeProvider = NotifierProvider<PrefNotifier<bool>, bool>(() {
  return PrefNotifier<bool>('amoled_mode', false);
});

final showSongInfoProvider = NotifierProvider<PrefNotifier<bool>, bool>(() {
  return PrefNotifier<bool>('show_song_info', true);
});

final extraControlsProvider = NotifierProvider<PrefNotifier<bool>, bool>(() {
  return PrefNotifier<bool>('extra_controls', false);
});

final showVolumeSliderProvider = NotifierProvider<PrefNotifier<bool>, bool>(() {
  return PrefNotifier<bool>('show_volume_slider', false);
});

/// Crossfade duration in seconds (0 = disabled, 1-12 range)
final crossfadeDurationProvider = NotifierProvider<PrefNotifier<int>, int>(() {
  return PrefNotifier<int>('crossfade_duration', 0);
});

/// Minimum song duration filter in seconds (songs shorter are hidden from library)
final minSongDurationProvider = NotifierProvider<PrefNotifier<int>, int>(() {
  return PrefNotifier<int>('min_song_duration', 30);
});

/// Whether to start playing when headphones/bluetooth are connected
final autoPlayOnConnectProvider = NotifierProvider<PrefNotifier<bool>, bool>(
  () {
    return PrefNotifier<bool>('auto_play_on_connect', false);
  },
);

/// Manual lyrics sync offset in milliseconds, applied to the playback position
/// that drives lyric highlighting. Positive shifts lyrics earlier, negative
/// delays them — compensates for audio-output latency so timing feels exact.
final lyricsOffsetProvider = NotifierProvider<PrefNotifier<int>, int>(() {
  return PrefNotifier<int>('lyrics_offset_ms', 0);
});

class SongLyricsOffsetNotifier extends Notifier<int> {
  final int songId;
  SongLyricsOffsetNotifier(this.songId);

  @override
  int build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    return prefs.getInt('lyrics_offset_ms_$songId') ?? 0;
  }

  void update(int value) {
    state = value;
    final prefs = ref.read(sharedPreferencesProvider);
    prefs.setInt('lyrics_offset_ms_$songId', value);
  }
}

final songLyricsOffsetProvider = NotifierProvider.family<SongLyricsOffsetNotifier, int, int>((arg) {
  return SongLyricsOffsetNotifier(arg);
});
