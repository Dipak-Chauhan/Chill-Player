class LyricWord {
  final Duration startTime;
  final Duration endTime;
  final String text;
  final String? romanText;

  const LyricWord({
    required this.startTime,
    required this.endTime,
    required this.text,
    this.romanText,
  });

  Map<String, dynamic> toJson() => {
    's': startTime.inMilliseconds,
    'e': endTime.inMilliseconds,
    't': text,
    if (romanText != null) 'r': romanText,
  };

  factory LyricWord.fromJson(Map<String, dynamic> json) => LyricWord(
    startTime: Duration(milliseconds: (json['s'] as num?)?.toInt() ?? 0),
    endTime: Duration(milliseconds: (json['e'] as num?)?.toInt() ?? 0),
    text: json['t'] as String? ?? '',
    romanText: json['r'] as String?,
  );
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

  Map<String, dynamic> toJson() => {
    's': startTime.inMilliseconds,
    'e': endTime.inMilliseconds,
    't': text,
    if (words != null) 'w': words!.map((w) => w.toJson()).toList(),
    if (backgroundLines != null)
      'b': backgroundLines!.map((l) => l.toJson()).toList(),
    if (isGap) 'g': 1,
    if (singer != null) 'si': singer,
    if (singerSide != null) 'ss': singerSide,
  };

  factory LyricLine.fromJson(Map<String, dynamic> json) => LyricLine(
    startTime: Duration(milliseconds: (json['s'] as num?)?.toInt() ?? 0),
    endTime: Duration(milliseconds: (json['e'] as num?)?.toInt() ?? 0),
    text: json['t'] as String? ?? '',
    words: (json['w'] as List?)
        ?.map((e) => LyricWord.fromJson(e as Map<String, dynamic>))
        .toList(),
    backgroundLines: (json['b'] as List?)
        ?.map((e) => LyricLine.fromJson(e as Map<String, dynamic>))
        .toList(),
    isGap: json['g'] == 1,
    singer: json['si'] as String?,
    singerSide: json['ss'] as String?,
  );

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
