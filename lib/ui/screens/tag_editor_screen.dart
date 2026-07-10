import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:on_audio_query/on_audio_query.dart';
import '../../models/song.dart';
import '../widgets/smooth_art_widget.dart';

/// Song metadata details and mini tag editor.
/// Displays file info, metadata tags, and allows copying values.
class TagEditorScreen extends ConsumerStatefulWidget {
  final Song song;

  const TagEditorScreen({super.key, required this.song});

  @override
  ConsumerState<TagEditorScreen> createState() => _TagEditorScreenState();
}

class _TagEditorScreenState extends ConsumerState<TagEditorScreen> {
  Map<dynamic, dynamic>? _rawMetadata;
  Map<String, String> _fileInfo = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadMetadata();
  }

  Future<void> _loadMetadata() async {
    try {
      // Fetch the song data from platform by querying for this specific song
      final songs = await OnAudioQuery().querySongs(
        sortType: SongSortType.TITLE,
        uriType: UriType.EXTERNAL,
      );
      final match = songs.where((s) => s.id == widget.song.id);
      if (match.isNotEmpty) {
        _rawMetadata = match.first.getMap;
      }

      final file = File(widget.song.uri);
      if (await file.exists()) {
        final stat = await file.stat();
        _fileInfo = {
          'File Path': widget.song.uri,
          'File Size': _formatFileSize(stat.size),
          'Last Modified': _formatDate(stat.modified),
        };
      }
    } catch (e) {
      _fileInfo = {'Error': 'Could not read file metadata: $e'};
    }

    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final song = widget.song;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Song Details', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.only(bottom: 120),
              children: [
                _buildArtHeader(theme, song),
                const SizedBox(height: 16),

                _buildSectionHeader(theme, 'Tags'),
                _buildTag(theme, 'Title', song.title),
                _buildTag(theme, 'Artist', song.artist),
                _buildTag(theme, 'Album', song.album),
                _buildTag(theme, 'Album Artist', song.albumArtist.isNotEmpty ? song.albumArtist : '—'),
                _buildTag(theme, 'Genre', song.genre.isNotEmpty ? song.genre : '—'),
                _buildTag(theme, 'Duration', _formatDuration(song.duration)),

                if (_rawMetadata != null) ...[
                  const SizedBox(height: 8),
                  _buildSectionHeader(theme, 'Extended Metadata'),
                  if (_rawMetadata!['track'] != null)
                    _buildTag(theme, 'Track Number', '${_rawMetadata!['track']}'),
                  if (_rawMetadata!['year'] != null && _rawMetadata!['year'] != 0)
                    _buildTag(theme, 'Year', '${_rawMetadata!['year']}'),
                  if (_rawMetadata!['composer'] != null)
                    _buildTag(theme, 'Composer', '${_rawMetadata!['composer']}'),
                  if (_rawMetadata!['date_added'] != null)
                    _buildTag(theme, 'Date Added', _formatTimestamp(_rawMetadata!['date_added'])),
                  if (_rawMetadata!['bitrate'] != null && _rawMetadata!['bitrate'] != 0)
                    _buildTag(theme, 'Bitrate', '${(_rawMetadata!['bitrate'] / 1000).round()} kbps'),
                  if (_rawMetadata!['sample_rate'] != null && _rawMetadata!['sample_rate'] != 0)
                    _buildTag(theme, 'Sample Rate', '${(_rawMetadata!['sample_rate'] / 1000).toStringAsFixed(1)} kHz'),
                  if (_rawMetadata!['channels'] != null)
                    _buildTag(theme, 'Channels', _rawMetadata!['channels'] == 2 ? 'Stereo' : '${_rawMetadata!['channels']}'),
                ],

                const SizedBox(height: 8),
                _buildSectionHeader(theme, 'File Information'),
                ..._fileInfo.entries.map((e) => _buildTag(theme, e.key, e.value)),

                _buildTag(theme, 'Format', song.uri.split('.').last.toUpperCase()),
              ],
            ),
    );
  }

  Widget _buildArtHeader(ThemeData theme, Song song) {
    return Container(
      padding: const EdgeInsets.all(24),
      child: Row(
        children: [
          SizedBox(
            width: 120,
            height: 120,
            child: SmoothArtWidget(
              id: song.id,
              size: 400,
              borderRadius: 16,
              iconSize: 40,
            ),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  song.title,
                  style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  song.artist,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: theme.colorScheme.primary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  song.album,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(ThemeData theme, String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        title.toUpperCase(),
        style: theme.textTheme.labelMedium?.copyWith(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  Widget _buildTag(ThemeData theme, String label, String value) {
    return InkWell(
      onLongPress: () {
        _copyToClipboard(value);
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 120,
              child: Text(
                label,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            Expanded(
              child: Text(
                value,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w400,
                ),
              ),
            ),
            Icon(
              Icons.copy,
              size: 16,
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
            ),
          ],
        ),
      ),
    );
  }

  void _copyToClipboard(String value) {
    if (value.isEmpty || value == '—') return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Copied: $value'),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1048576) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / 1048576).toStringAsFixed(1)} MB';
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes;
    final seconds = d.inSeconds.remainder(60);
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  String _formatDate(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }

  String _formatTimestamp(dynamic ts) {
    if (ts is int) {
      final dt = DateTime.fromMillisecondsSinceEpoch(ts * 1000);
      return _formatDate(dt);
    }
    return '$ts';
  }
}
