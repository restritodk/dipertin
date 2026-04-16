// Limpeza completa: na pasta do app execute: dart run tool/clean.dart
// Usa a pasta do script (não o diretório atual) para achar build/ e flutter-apk.
import 'dart:io';

Future<void> main() async {
  final root = _raizDoProjeto();
  stderr.writeln('Raiz do projeto: ${root.path}');

  stderr.writeln('→ flutter clean');
  await _run('flutter', ['clean'], root);

  final androidDir = Directory(joinPath(root.path, ['android']));
  final gradlew = Platform.isWindows ? 'gradlew.bat' : 'gradlew';
  final gradlewPath = joinPath(androidDir.path, [gradlew]);
  if (File(gradlewPath).existsSync()) {
    stderr.writeln('→ gradle clean');
    await _run(gradlewPath, ['clean', '--no-daemon'], Directory(androidDir.path));
  }

  final saidas = <List<String>>[
    ['build', 'app', 'outputs', 'flutter-apk'],
    ['build', 'app', 'outputs', 'apk'],
    ['build', 'app', 'outputs', 'bundle'],
    ['build', 'app', 'outputs'],
    ['build'],
    ['android', 'app', 'build'],
  ];

  stderr.writeln('→ apagando saídas (flutter-apk, apk, build/)');
  for (final rel in saidas) {
    await _apagarPastaOuArquivo(joinPath(root.path, rel));
  }

  stderr.writeln('Concluído.');
}

/// Pasta com `pubspec.yaml` (este ficheiro: `<proj>/tool/clean.dart`).
Directory _raizDoProjeto() {
  try {
    final script = File(Platform.script.toFilePath());
    final dirProjeto = script.parent.parent;
    if (File(joinPath(dirProjeto.path, ['pubspec.yaml'])).existsSync()) {
      return dirProjeto;
    }
  } catch (_) {}

  var cur = Directory.current;
  for (var i = 0; i < 8; i++) {
    if (File(joinPath(cur.path, ['pubspec.yaml'])).existsSync()) {
      return cur;
    }
    final parent = cur.parent;
    if (parent.path == cur.path) break;
    cur = parent;
  }
  return Directory.current;
}

String joinPath(String root, List<String> parts) {
  if (parts.isEmpty) return root;
  return [root, ...parts].join(Platform.pathSeparator);
}

Future<void> _run(String command, List<String> args, Directory workingDir) async {
  final r = await Process.run(
    command,
    args,
    workingDirectory: workingDir.path,
    runInShell: true,
  );
  stdout.write(r.stdout);
  stderr.write(r.stderr);
}

Future<void> _apagarPastaOuArquivo(String caminhoAbsoluto) async {
  final tipo = FileSystemEntity.typeSync(caminhoAbsoluto);
  if (tipo == FileSystemEntityType.notFound) return;

  try {
    if (tipo == FileSystemEntityType.file) {
      await File(caminhoAbsoluto).delete();
      return;
    }
    await Directory(caminhoAbsoluto).delete(recursive: true);
    return;
  } catch (e) {
    stderr.writeln('Dart não apagou $caminhoAbsoluto: $e');
  }

  if (!Platform.isWindows) return;

  // Fallback Windows: ficheiros em uso impedem Directory.delete() em Dart
  final r = await Process.run(
    'cmd',
    ['/c', 'rmdir', '/s', '/q', caminhoAbsoluto],
    runInShell: true,
  );
  if (r.exitCode != 0 || FileSystemEntity.typeSync(caminhoAbsoluto) != FileSystemEntityType.notFound) {
    final esc = caminhoAbsoluto.replaceAll("'", "''");
    await Process.run(
      'powershell',
      [
        '-NoProfile',
        '-Command',
        "Remove-Item -LiteralPath '$esc' -Recurse -Force -ErrorAction SilentlyContinue",
      ],
      runInShell: true,
    );
  }
}
