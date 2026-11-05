// A dependency-free smoke test for generation boundaries. Run from any directory:
// dart run tool/generator_smoke_test.dart
import 'dart:io';

Future<void> main() async {
  final root = File.fromUri(Platform.script).parent.parent;
  final vendor = Directory('${root.path}/vendor/highlight.js');
  if (!File('${vendor.path}/src/languages/plaintext.js').existsSync()) {
    stderr.writeln('Initialize vendor/highlight.js before running this test.');
    exitCode = 1;
    return;
  }
  final temporary = Directory.systemTemp.createTempSync('highlight-generator-');
  try {
    final tool = Directory('${temporary.path}/tool')..createSync();
    File('${root.path}/tool/generate_languages.dart')
        .copySync('${tool.path}/generate_languages.dart');
    Directory('${temporary.path}/vendor').createSync();
    Link('${temporary.path}/vendor/highlight.js').createSync(vendor.path);
    final languages = Directory('${temporary.path}/highlight/lib/languages')
      ..createSync(recursive: true);
    final registry = File('${temporary.path}/highlight/lib/highlight.dart')
      ..writeAsStringSync('// limited registry sentinel\n');
    for (final name in ['plaintext', 'vue', 'solidity']) {
      File('${languages.path}/$name.dart')
          .writeAsStringSync('// $name hand-port sentinel\n');
    }
    Future<ProcessResult> run(List<String> arguments) => Process.run(
      Platform.resolvedExecutable,
      ['${tool.path}/generate_languages.dart', ...arguments],
      workingDirectory: temporary.path,
    );
    final generated = await run(['--no-format']);
    _check(generated.exitCode == 0, '${generated.stdout}\n${generated.stderr}');
    _check(
      File('${languages.path}/plaintext.dart')
          .readAsStringSync()
          .contains('Mode plaintext(Highlight hljs)'),
      'Expected a current-API plaintext grammar',
    );
    for (final name in ['vue', 'solidity']) {
      _check(
        File('${languages.path}/$name.dart').readAsStringSync() ==
            '// $name hand-port sentinel\n',
        '$name hand-port was overwritten',
      );
      final requested = await run([name]);
      _check(requested.exitCode == 0, 'Explicit $name request failed');
    }
    _check(
      registry.readAsStringSync() == '// limited registry sentinel\n',
      'Limited default registry was overwritten',
    );
    final all = File('${languages.path}/_all.dart').readAsStringSync();
    _check(all.contains("registerLanguage('vue'"), 'Missing opt-in Vue');
    _check(
      all.contains("registerLanguage('solidity'"),
      'Missing opt-in Solidity',
    );
    final invalid = await run(['--unknown']);
    _check(invalid.exitCode == 64, 'Unknown option must fail');
    stdout.writeln('Generator smoke test passed.');
  } finally {
    temporary.deleteSync(recursive: true);
  }
}

void _check(bool condition, String message) {
  if (!condition) throw StateError(message);
}
