import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dynamic_color/dynamic_color.dart';
import 'package:animations/animations.dart';

import 'theme/app_theme.dart';
import 'ui/screens/home_screen.dart';
import 'state/audio_state.dart';
import 'theme/color_provider.dart';
import 'services/settings_service.dart';
import 'package:audio_service/audio_service.dart';
import 'services/audio_handler.dart';


void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Keep more decoded artwork resident so fast library scrolling stays smooth.
  PaintingBinding.instance.imageCache.maximumSizeBytes = 150 << 20; // 150 MB
  
  final audioHandler = await AudioService.init(
    builder: () => ChillAudioHandler(),
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.ryanheise.bg_audio.channel.audio',
      androidNotificationChannelName: 'Audio playback',
      androidNotificationOngoing: true,
      androidShowNotificationBadge: true,
    ),
  );
  
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarDividerColor: Colors.transparent,
  ));
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  
  final prefs = await SharedPreferences.getInstance();

  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        audioHandlerProvider.overrideWithValue(audioHandler),
      ],
      child: const ChillPlayerApp(),
    ),
  );
}

class ChillPlayerApp extends ConsumerWidget {
  const ChillPlayerApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorSchemeState = ref.watch(colorSchemeProvider);
    final hasSong = ref.watch(currentSongProvider.select((s) => s != null));
    final themeModeStr = ref.watch(themeModeProvider);

    final ThemeMode themeMode;
    switch (themeModeStr) {
      case 'light':
        themeMode = ThemeMode.light;
        break;
      case 'dark':
        themeMode = ThemeMode.dark;
        break;
      default:
        themeMode = ThemeMode.system;
    }

    return DynamicColorBuilder(
      builder: (lightDynamic, darkDynamic) {
        ColorScheme lightScheme = colorSchemeState.light;
        ColorScheme darkScheme = colorSchemeState.dark;
        
        if (!hasSong && lightDynamic != null && darkDynamic != null) {
          lightScheme = lightDynamic;
          darkScheme = darkDynamic;
        }

        return AnimatedTheme(
          data: themeMode == ThemeMode.light
             ? AppTheme.buildTheme(lightScheme.primary, Brightness.light)
             : AppTheme.buildTheme(darkScheme.primary, Brightness.dark),
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeInOut,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            title: 'Chill Player',
            themeMode: themeMode,
            theme: AppTheme.buildTheme(lightScheme.primary, Brightness.light),
            darkTheme: AppTheme.buildTheme(darkScheme.primary, Brightness.dark),
            home: const MainWrapper(),
            onGenerateRoute: (settings) {
              // M3E Route Transitions Wrapper
              return PageRouteBuilder(
                 pageBuilder: (context, animation, secondaryAnimation) {
                   // Just returning a dummy scaffold to prevent crashes here,
                   // actual routing is done elsewhere or we define explicit routes in routes map.
                   // As we migrate screens we can wire them properly.
                   return const Scaffold(); 
                 },
                 transitionsBuilder: (context, animation, secondaryAnimation, child) {
                   if (settings.name == '/now_playing') {
                      return SharedAxisTransition(
                        animation: animation,
                        secondaryAnimation: secondaryAnimation,
                        transitionType: SharedAxisTransitionType.vertical,
                        child: child,
                      );
                   }
                   if (settings.name == '/search' || settings.name == '/playlists' || settings.name == '/equalizer' || settings.name?.startsWith('/artist') == true) {
                      return SharedAxisTransition(
                        animation: animation,
                        secondaryAnimation: secondaryAnimation,
                        transitionType: SharedAxisTransitionType.horizontal,
                        child: child,
                      );
                   }
                   if (settings.name == '/settings' || settings.name == '/settings/themes') {
                      return FadeThroughTransition(
                        animation: animation,
                        secondaryAnimation: secondaryAnimation,
                        child: child,
                      );
                   }
                   return FadeThroughTransition(
                      animation: animation,
                      secondaryAnimation: secondaryAnimation,
                      child: child,
                   );
                 }
              );
            },
          )
        );
      },
    );
  }
}

class MainWrapper extends ConsumerStatefulWidget {
  const MainWrapper({super.key});

  @override
  ConsumerState<MainWrapper> createState() => _MainWrapperState();
}

class _MainWrapperState extends ConsumerState<MainWrapper> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final currentSong = ref.read(currentSongProvider);
      if (currentSong != null) {
        ColorExtractor.extractColors(ref, currentSong.id);
      }
    });

    ref.listenManual(currentSongProvider, (previous, next) {
      if (next != null && next.id != previous?.id) {
        ColorExtractor.extractColors(ref, next.id);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: HomeScreen(),
    );
  }
}
