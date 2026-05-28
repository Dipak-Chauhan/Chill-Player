import 'dart:io';

void main() {
  final dir = Directory('c:/Users/User/Music/Chill Player/lib');
  final files = dir.listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'));

  for (final file in files) {
    if (file.path.contains('m3_loading_indicator.dart') || file.path.contains('home_screen.dart')) continue;

    var content = file.readAsStringSync();
    if (content.contains('CircularProgressIndicator')) {
      content = content.replaceAll(RegExp(r'const CircularProgressIndicator()', multiLine: true), 'const M3LoadingIndicator(size: 40)');
      content = content.replaceAll(RegExp(r'CircularProgressIndicator()', multiLine: true), 'M3LoadingIndicator(size: 40)');
      
      // Calculate depth dynamically from lib/
      final parts = file.path.replaceAll('\\\\', '/').split('/lib/').last.split('/');
      final upDirs = parts.length > 2 ? List.filled(parts.length - 2, '../').join('') : '';
      final importPath = "import '${upDirs}widgets/m3_loading_indicator.dart';";

      if (!content.contains('m3_loading_indicator.dart')) {
        content = content.replaceFirst("import 'package:flutter/material.dart';", "import 'package:flutter/material.dart';\n$importPath");
      }
      
      file.writeAsStringSync(content);
      print('Updated ${file.path}');
    }
  }
}
