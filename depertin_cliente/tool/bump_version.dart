// Sobe versionName + versionCode no pubspec.yaml (regra DiPertin).
//
// Uso na pasta do app:
//   dart run tool/bump_version.dart
//   dart run tool/bump_version.dart --dry-run
//
// Regra: 1.2.5 → 1.2.6 → … → 1.2.9 → 1.3.0 (patch só vai até 9).
import 'dart:io';

void main(List<String> args) {
  final dryRun = args.contains('--dry-run');
  final root = _raizDoProjeto();
  final pubspec = File('${root.path}/pubspec.yaml');
  if (!pubspec.existsSync()) {
    stderr.writeln('pubspec.yaml não encontrado em ${root.path}');
    exitCode = 1;
    return;
  }

  final linhas = pubspec.readAsLinesSync();
  final idx = linhas.indexWhere((l) => l.startsWith('version:'));
  if (idx < 0) {
    stderr.writeln('Linha version: não encontrada no pubspec.yaml');
    exitCode = 1;
    return;
  }

  final atual = _parseVersionLine(linhas[idx]);
  final proximoNome = _proximoVersionName(atual.name);
  final proximoBuild = atual.build + 1;
  final novaLinha = 'version: $proximoNome+$proximoBuild';

  stderr.writeln(
    '${dryRun ? "[dry-run] " : ""}${atual.name}+${atual.build} → $proximoNome+$proximoBuild',
  );

  if (dryRun) return;

  linhas[idx] = novaLinha;
  pubspec.writeAsStringSync('${linhas.join('\n')}\n');

  _sincronizarSobreFallback(root, proximoNome);

  stderr.writeln('Atualizado: pubspec.yaml e lib/screens/comum/sobre_screen.dart');
  stderr.writeln('Próximo passo: flutter build appbundle --release');
}

/// Patch 0–9; ao passar de .9 sobe o minor e volta patch para 0.
String _proximoVersionName(String atual) {
  final partes = atual.split('.');
  if (partes.length != 3) {
    stderr.writeln('versionName inválido: $atual (esperado major.minor.patch)');
    exit(1);
  }
  final major = int.tryParse(partes[0]);
  final minor = int.tryParse(partes[1]);
  final patch = int.tryParse(partes[2]);
  if (major == null || minor == null || patch == null) {
    stderr.writeln('versionName inválido: $atual');
    exit(1);
  }
  if (patch < 9) {
    return '$major.$minor.${patch + 1}';
  }
  return '$major.${minor + 1}.0';
}

({String name, int build}) _parseVersionLine(String linha) {
  final m = RegExp(r'^version:\s*(\d+\.\d+\.\d+)\+(\d+)\s*$').firstMatch(linha);
  if (m == null) {
    stderr.writeln('Formato esperado: version: 1.2.6+22');
    exit(1);
  }
  return (name: m.group(1)!, build: int.parse(m.group(2)!));
}

void _sincronizarSobreFallback(Directory root, String versao) {
  final sobre = File('${root.path}/lib/screens/comum/sobre_screen.dart');
  if (!sobre.existsSync()) return;

  var texto = sobre.readAsStringSync();
  texto = texto.replaceFirst(
    RegExp(
      r"/// Texto exibido em Sobre — alinhar com \[pubspec\.yaml\] version \(\d+\.\d+\.\d+\)\.",
    ),
    '/// Texto exibido em Sobre — alinhar com [pubspec.yaml] version ($versao).',
  );
  texto = texto.replaceFirst(
    RegExp(r"const String _versaoFallback = '\d+\.\d+\.\d+';"),
    "const String _versaoFallback = '$versao';",
  );
  sobre.writeAsStringSync(texto);
}

Directory _raizDoProjeto() {
  final script = File(Platform.script.toFilePath());
  return script.parent.parent;
}
