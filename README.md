# 🎵 Chill Player

A premium, modern Flutter music player featuring responsive Material 3 design, dynamic color extraction, and advanced word-by-word synchronized lyrics.

> [!WARNING]
> **Active Development Warning**
> This project is currently under active development. Many features, APIs, and screens are in progress and might not work reliably or could change significantly.

---

## ✨ Features

### 1. 🎤 Advanced Lyrics Engine (Apple-Music-Style)
- **Word-by-Word Synced Highlight**: Precise word-level synchronization utilizing YouLy+ gradient wipe animations.
- **Multi-Source Fetch Pipeline**: Automatically queries lyrics with fallback cascading across multiple providers:
  - **BiniLyrics API** (High-fidelity syllable-synced Apple Music TTML)
  - **LyricsPlus (KPOE)** (Syllable-synced /v2 JSON)
  - **Musixmatch Richsync** (Word-by-word timing verification)
  - **Unison API / LRCLIB** (Line-synced LRC fallback)
- **Translation & Romanization**: Real-time batch translation and CJK script romanization using free Google Translate APIs, maintaining syllable mapping.
- **Predictive Scroll**: Dynamic viewport centering based on current playing offset and upcoming gaps.
- **Local Lyrics Editor**: Custom lyrics saving/editing support for TTML, LRC, and plain text.
- **Duet Layouts**: Separate left/right layout mapping for dual-singer vocals.

### 2. 🎛️ Audio Core & Playback Persistence
- **Background Playback**: Full background controls and media notifications powered by `audio_service` and `just_audio`.
- **ExoPlayer Swapping Firewall**: Custom playback status proxy that prevents UI flickering during large native playlist exchanges.
- **Crossfade Logic**: Smooth audio crossfades on track completion.
- **State Recovery**: Restores playback queue, active track index, and seek position automatically upon reopening the application.
- **Wakelock Integration**: Optional screen lock prevention while viewing scrolling lyrics.

### 3. 🎨 Dynamic Visuals & Premium UI
- **Dynamic color extraction**: Quantizes and weights album artwork colors to generate matching seed Material 3 color palettes on-the-fly.
- **Dithered Frosted Glass**: Procedural grain/noise overlay that breaks up banding artifacts in translucent panels.
- **Wavy Seekbar**: Material 3 expressive squiggly progress bar that changes waveform amplitude based on playback states.
- **Venom Elastic Physics**: Liquid-stretch scroll pull actions on interaction targets.
- **Mini-Player Morphing**: Smooth container transforms scaling the bottom bar directly into the Full Now Playing view.
- **Haptic tactile ticking**: Custom haptic feedback engine optimized for letter indexing and sliders.

### 4. 📂 Smart Media Library
- **Intelligent Sorting**: Automated groupings by folders, genres, artists, and albums.
- **Artist Separation**: Advanced parsing engine to split collaborating artist groupings (`feat.`, `ft.`, `&`, `x`, `with`) for separate statistics.
- **Deezer Artwork Cache**: Asynchronously fetches and stores artist profile images using persistent disk LRU caches to bypass API rate-limiting.
- **Listening Statistics**: Aggregates total listening time, top-played tracks, and daily mixes.

---

## 🛠️ Technology Stack
- **Framework**: [Flutter](https://flutter.dev) (Dart)
- **State Management**: [Riverpod](https://riverpod.dev)
- **Audio engine**: [just_audio](https://pub.dev/packages/just_audio) & [audio_service](https://pub.dev/packages/audio_service)
- **Theming**: Material 3 & [dynamic_color](https://pub.dev/packages/dynamic_color)
- **Animations**: Flutter Animations package (Shared Axis / Fade Through Transitions)

---

## 🚀 Getting Started

### Prerequisites
- Flutter SDK (stable channel)
- Android SDK (for Android build) or Windows build tools

### Setup
1. Clone the repository:
   ```bash
   git clone https://github.com/Dipak-Chauhan/Chill-Player.git
   cd Chill-Player
   ```
2. Fetch dependencies:
   ```bash
   flutter pub get
   ```
3. Run the development build:
   ```bash
   flutter run
   ```
