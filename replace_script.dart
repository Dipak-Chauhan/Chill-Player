import 'dart:io';
void main() {
  final dir = Directory('lib');
  for (var file in dir.listSync(recursive: true)) {
    if (file is File && file.path.endsWith('.dart')) {
      var content = file.readAsStringSync();
      
      // withOpacity(x) -> withValues(alpha: x)
      var newContent = content.replaceAll(RegExp(r'\.withOpacity\('), '.withValues(alpha: ');
      
      // surfaceVariant -> surfaceContainerHighest (avoiding onSurfaceVariant)
      newContent = newContent.replaceAll(RegExp(r'(?<!on)[sS]urfaceVariant'), 'surfaceContainerHighest');
      
      if (content != newContent) {
        file.writeAsStringSync(newContent);
        print('Updated: ${file.path}');
      }
    }
  }
}
