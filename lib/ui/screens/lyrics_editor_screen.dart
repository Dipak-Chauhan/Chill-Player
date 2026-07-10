import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:on_audio_query/on_audio_query.dart';
import '../../models/song.dart';
import '../../services/local_lyrics_service.dart';
import '../../services/lrclib_api.dart';
import '../../theme/color_provider.dart';
import '../../state/audio_state.dart';
import '../../state/lyrics_provider.dart';

/// Full-screen lyrics editor allowing users to paste, type, or edit
/// LRC lyrics for the current song. Supports ELRC (TTML), synced LRC,
/// and plain text lyrics. Includes an API fetch button to grab lyrics
/// from the internet and save them locally for offline use.
class LyricsEditorScreen extends ConsumerStatefulWidget {
  final Song song;
  final String? existingLyrics;

  const LyricsEditorScreen({
    super.key,
    required this.song,
    this.existingLyrics,
  });

  @override
  ConsumerState<LyricsEditorScreen> createState() => _LyricsEditorScreenState();
}

class _LyricsEditorScreenState extends ConsumerState<LyricsEditorScreen> {
  late final TextEditingController _controller;
  bool _hasChanges = false;
  bool _isSaving = false;
  bool _isFetching = false;
  bool _hasLocalLyrics = false;
  String _fetchedType = ''; // Track what type was fetched for the banner

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.existingLyrics ?? '');
    _controller.addListener(_onTextChanged);
    _loadExisting();
  }

  void _onTextChanged() {
    if (!_hasChanges && mounted) setState(() => _hasChanges = true);
  }

  Future<void> _loadExisting() async {
    final hasLocal = await LocalLyricsService.hasCustomLyrics(widget.song.id);
    if (mounted) setState(() => _hasLocalLyrics = hasLocal);

    if (_controller.text.isEmpty && hasLocal) {
      final local = await LocalLyricsService.loadLyrics(widget.song.id);
      if (local != null && local.isNotEmpty && mounted) {
        _controller.removeListener(_onTextChanged);
        _controller.text = local;
        _controller.addListener(_onTextChanged);
        _hasChanges = false;
        if (LocalLyricsService.isTtml(local)) {
          _fetchedType = 'ELRC (syllable-synced)';
        }
      }
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onTextChanged);
    _controller.dispose();
    super.dispose();
  }

  /// Fetch lyrics with cascade: ELRC/TTML → LRC synced → plain text
  Future<void> _fetchFromApi() async {
    setState(() => _isFetching = true);

    String? fetchedLyrics;
    String fetchType = '';

    try {
      // 1. Try line-by-line synced LRC from LRCLib (hand-editable text).
      final synced = await LrcLibApi.fetchSyncedLyrics(
        widget.song.title,
        widget.song.artist,
        duration: widget.song.duration,
      );
      if (synced != null && synced.isNotEmpty) {
        fetchedLyrics = synced;
        fetchType = 'LRC (line-synced)';
      }

      // 3. Try plain/simple lyrics from LRCLib
      if (fetchedLyrics == null) {
        final plain = await LrcLibApi.fetchPlainLyrics(
          widget.song.title,
          widget.song.artist,
          duration: widget.song.duration,
        );
        if (plain != null && plain.isNotEmpty) {
          fetchedLyrics = plain;
          fetchType = 'Plain text (unsynced)';
        }
      }

      if (fetchedLyrics != null && mounted) {
        _controller.removeListener(_onTextChanged);
        _controller.text = fetchedLyrics;
        _controller.addListener(_onTextChanged);
        setState(() {
          _hasChanges = true;
          _isFetching = false;
          _fetchedType = fetchType;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Found $fetchType lyrics! Tap Save to keep offline.',
              ),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              duration: const Duration(seconds: 3),
            ),
          );
        }
      } else {
        if (mounted) {
          setState(() => _isFetching = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('No lyrics found online for this song'),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              duration: const Duration(seconds: 2),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isFetching = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to fetch: $e'),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  Future<void> _save() async {
    if (_controller.text.trim().isEmpty) return;
    setState(() => _isSaving = true);

    await LocalLyricsService.saveLyrics(
      songId: widget.song.id,
      lrcContent: _controller.text,
      title: widget.song.title,
      artist: widget.song.artist,
    );

    ref.invalidate(lyricsProvider);

    if (mounted) {
      setState(() {
        _isSaving = false;
        _hasChanges = false;
        _hasLocalLyrics = true;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Lyrics saved locally for offline use'),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _deleteCustom() async {
    if (!_hasLocalLyrics) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('No saved lyrics to delete'),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          duration: const Duration(seconds: 1),
        ),
      );
      return;
    }

    final confirm = await _showOpaqueDialog(
      title: 'Delete saved lyrics?',
      content:
          'This will remove your locally saved lyrics. The app will use auto-fetched lyrics from the internet.',
      confirmText: 'Delete',
    );

    if (confirm == true) {
      await LocalLyricsService.deleteLyrics(widget.song.id);
      ref.invalidate(lyricsProvider);
      if (mounted) {
        _controller.removeListener(_onTextChanged);
        _controller.clear();
        _controller.addListener(_onTextChanged);
        setState(() {
          _hasChanges = false;
          _hasLocalLyrics = false;
          _fetchedType = '';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Saved lyrics deleted'),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  Future<bool> _onWillPop() async {
    if (!_hasChanges) return true;
    final result = await _showOpaqueDialog(
      title: 'Unsaved changes',
      content: 'You have unsaved lyrics changes. Discard them?',
      cancelText: 'Keep editing',
      confirmText: 'Discard',
    );
    return result ?? false;
  }

  /// Shows a dialog with a guaranteed opaque background.
  Future<bool?> _showOpaqueDialog({
    required String title,
    required String content,
    String cancelText = 'Cancel',
    String confirmText = 'OK',
  }) {
    final brightness = Theme.of(context).brightness;
    // Use a solid, non-transparent background color
    final bgColor = brightness == Brightness.dark
        ? const Color(0xFF2D2D2D)
        : const Color(0xFFF5F5F5);

    return showDialog<bool>(
      context: context,
      barrierColor: Colors.black54,
      builder: (ctx) => AlertDialog(
        backgroundColor: bgColor,
        surfaceTintColor: Colors.transparent,
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(cancelText),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(confirmText),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = _controller.text;
    final isTtml = LocalLyricsService.isTtml(text);
    final hasTimestamps = RegExp(r'\[\d{1,2}:\d{2}\.\d{2,3}\]').hasMatch(text);

    final colors = ref.watch(currentExtractedColorsProvider);
    final accentColor = colors.vibrant;
    final isAmoled = ref.watch(nowPlayingAmoledProvider);

    // Determine status text
    String statusText;
    IconData statusIcon;
    if (_fetchedType == 'ELRC (syllable-synced)' || isTtml) {
      statusText = 'ELRC (syllable-synced) — Save to keep for offline playback';
      statusIcon = Icons.music_note_rounded;
    } else if (_hasLocalLyrics && !_hasChanges) {
      statusText = 'Locally saved lyrics — fallback when offline';
      statusIcon = Icons.save_alt_rounded;
    } else if (hasTimestamps) {
      statusText = 'Synced LRC detected — timestamps will highlight lines';
      statusIcon = Icons.timer_rounded;
    } else {
      statusText = 'Tap ☁️ to fetch lyrics, then Save for offline fallback';
      statusIcon = Icons.text_fields_rounded;
    }

    return PopScope(
      canPop: !_hasChanges,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final shouldPop = await _onWillPop();
        if (shouldPop && context.mounted) Navigator.of(context).pop();
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Background: album art blurred + dark overlay (matches LyricsScreen exactly)
          if (!isAmoled)
            Stack(
              fit: StackFit.expand,
              children: [
                ImageFiltered(
                  imageFilter: ImageFilter.blur(
                    sigmaX: 40,
                    sigmaY: 40,
                    tileMode: TileMode.clamp,
                  ),
                  child: Transform.scale(
                    scale: 1.15,
                    child: QueryArtworkWidget(
                      id: widget.song.id,
                      type: ArtworkType.AUDIO,
                      quality: 25,
                      size: 300,
                      artworkFit: BoxFit.cover,
                      artworkWidth: double.infinity,
                      artworkHeight: double.infinity,
                      nullArtworkWidget: Container(
                        color: const Color(0xFF1A1A1A),
                      ),
                      keepOldArtwork: true,
                    ),
                  ),
                ),
                Container(color: Colors.black.withValues(alpha: 0.60)),
                // Frosted glass overlay (matches options sheet)
                BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                  child: Container(
                    color: const Color(0x80141414), // frosted sheet tint
                  ),
                ),
              ],
            )
          else
            Container(color: Colors.black),
          // Scaffold UI
          Scaffold(
            backgroundColor: Colors.transparent,
            appBar: AppBar(
              backgroundColor: Colors.transparent,
              elevation: 0,
              leading: IconButton(
                icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                onPressed: () async {
                  final shouldPop = await _onWillPop();
                  if (shouldPop && context.mounted) Navigator.of(context).pop();
                },
              ),
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Edit Lyrics',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${widget.song.title} — ${widget.song.artist}',
                    style: const TextStyle(
                      color: Colors.white60,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
              actions: [
                IconButton(
                  icon: _isFetching
                      ? SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: accentColor,
                          ),
                        )
                      : const Icon(
                          Icons.cloud_download_outlined,
                          color: Colors.white70,
                        ),
                  tooltip: 'Fetch lyrics from internet',
                  onPressed: _isFetching ? null : _fetchFromApi,
                ),
                IconButton(
                  icon: Icon(
                    Icons.delete_outline_rounded,
                    color: _hasLocalLyrics
                        ? theme.colorScheme.error
                        : Colors.white70,
                  ),
                  tooltip: 'Delete saved lyrics',
                  onPressed: _deleteCustom,
                ),
                IconButton(
                  icon: _isSaving
                      ? SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: accentColor,
                          ),
                        )
                      : Icon(
                          Icons.save_rounded,
                          color: _hasChanges ? accentColor : Colors.white30,
                        ),
                  tooltip: 'Save lyrics locally',
                  onPressed: _hasChanges ? _save : null,
                ),
              ],
            ),
            body: Column(
              children: [
                // Floating status banner card
                Container(
                  margin: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: accentColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: accentColor.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: accentColor.withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(statusIcon, size: 20, color: accentColor),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Text(
                          statusText,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                // Editor glass card
                Expanded(
                  child: Container(
                    margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.03),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.08),
                      ),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: isTtml
                          // TTML/ELRC: Show a read-only preview since XML isn't meant to be hand-edited
                          ? _buildTtmlPreview(theme, accentColor)
                          : Theme(
                              data: theme.copyWith(
                                textSelectionTheme: TextSelectionThemeData(
                                  cursorColor: accentColor,
                                  selectionColor: accentColor.withValues(
                                    alpha: 0.3,
                                  ),
                                  selectionHandleColor: accentColor,
                                ),
                              ),
                              child: TextField(
                                controller: _controller,
                                maxLines: null,
                                expands: true,
                                textAlignVertical: TextAlignVertical.top,
                                keyboardType: TextInputType.multiline,
                                decoration: InputDecoration(
                                  hintText:
                                      'Paste or type lyrics here...\n\n'
                                      'Or tap the cloud fetch button above to grab\n'
                                      'lyrics from the internet.\n\n'
                                      'Synced LRC format example:\n'
                                      '[00:12.00]First line of lyrics\n'
                                      '[00:17.20]Second line of lyrics',
                                  hintStyle: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.25),
                                    fontSize: 14,
                                  ),
                                  border: InputBorder.none,
                                  contentPadding: const EdgeInsets.all(20),
                                ),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontFamily: 'monospace',
                                  fontSize: 13,
                                  height: 1.6,
                                ),
                              ),
                            ),
                    ),
                  ),
                ),
              ],
            ),
            floatingActionButton: FloatingActionButton.small(
              onPressed: () => _showFormatHelp(context, accentColor),
              backgroundColor: accentColor.withValues(alpha: 0.2),
              foregroundColor: accentColor,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: accentColor.withValues(alpha: 0.4)),
              ),
              tooltip: 'LRC format help',
              child: const Icon(Icons.help_outline_rounded),
            ),
          ),
        ],
      ),
    );
  }

  /// Shows a friendly preview for TTML/ELRC data instead of raw XML
  Widget _buildTtmlPreview(ThemeData theme, Color accentColor) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ELRC badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: accentColor.withValues(alpha: 0.3)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.music_note_rounded, size: 22, color: accentColor),
                const SizedBox(width: 10),
                Text(
                  'ELRC — Syllable-Synced Lyrics',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'This song has enhanced syllable-by-syllable synced lyrics (Apple Music style). '
            'Tap Save to keep them for offline playback.',
            style: TextStyle(color: Colors.white60, fontSize: 14, height: 1.5),
          ),
          const SizedBox(height: 24),
          // Show raw data in a collapsed expandable
          Theme(
            data: theme.copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              title: const Text(
                'View raw TTML data',
                style: TextStyle(
                  color: Colors.white38,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              tilePadding: EdgeInsets.zero,
              iconColor: Colors.white38,
              collapsedIconColor: Colors.white38,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.03),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.05),
                    ),
                  ),
                  child: SelectableText(
                    _controller.text,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontFamily: 'monospace',
                      fontSize: 11,
                      height: 1.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showFormatHelp(BuildContext context, Color accentColor) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      elevation: 0,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xE6141414), // Frosted glass sheet color
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(28),
              ),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.08),
                width: 1,
              ),
            ),
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 20),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Lyrics Format Guide',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.close_rounded,
                        color: Colors.white60,
                        size: 20,
                      ),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _helpRow(
                  theme,
                  'ELRC',
                  'Syllable-synced (fetched automatically, best quality)',
                  accentColor,
                ),
                const SizedBox(height: 12),
                _helpRow(
                  theme,
                  '[00:12.50]',
                  'LRC — Line-by-line synced lyrics',
                  accentColor,
                ),
                const SizedBox(height: 12),
                _helpRow(
                  theme,
                  'Plain Text',
                  'Unsynced lyrics (no timestamps)',
                  accentColor,
                ),
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: accentColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: accentColor.withValues(alpha: 0.25),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.lightbulb_outline_rounded,
                        size: 20,
                        color: accentColor,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Tap the cloud fetch button above to grab the best lyrics available. ELRC provides word-by-word highlights like Apple Music.',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.85),
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            height: 1.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _helpRow(
    ThemeData theme,
    String code,
    String desc,
    Color accentColor,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: accentColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: accentColor.withValues(alpha: 0.25)),
          ),
          child: Text(
            code,
            style: TextStyle(
              color: accentColor,
              fontFamily: 'monospace',
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 4.0),
            child: Text(
              desc,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
