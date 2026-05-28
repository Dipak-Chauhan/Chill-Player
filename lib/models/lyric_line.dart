class LyricWord {
  final Duration startTime;
  final Duration endTime;
  final String text;

  const LyricWord({
    required this.startTime,
    required this.endTime,
    required this.text,
  });
}

class LyricLine {
  final Duration startTime;
  final Duration endTime;
  final String text;
  final List<LyricWord>? words;
  final List<LyricLine>? backgroundLines;
  /// True if this line is an instrumental gap (no text, shows dots)
  final bool isGap;
  final String? singer;
  final String? singerSide; // 'left', 'right', 'center'

  const LyricLine({
    required this.startTime,
    required this.endTime,
    required this.text,
    this.words,
    this.backgroundLines,
    this.isGap = false,
    this.singer,
    this.singerSide,
  });

  LyricLine copyWith({
    Duration? startTime,
    Duration? endTime,
    String? text,
    List<LyricWord>? words,
    List<LyricLine>? backgroundLines,
    bool? isGap,
    String? singer,
    String? singerSide,
  }) {
    return LyricLine(
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      text: text ?? this.text,
      words: words ?? this.words,
      backgroundLines: backgroundLines ?? this.backgroundLines,
      isGap: isGap ?? this.isGap,
      singer: singer ?? this.singer,
      singerSide: singerSide ?? this.singerSide,
    );
  }
}
