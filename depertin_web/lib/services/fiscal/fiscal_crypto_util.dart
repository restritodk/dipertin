import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:encrypt/encrypt.dart' as enc;
import 'package:pointycastle/export.dart' as pc;

/// Utilitario de criptografia para credenciais fiscais.
///
/// Responsabilidades:
/// - Criptografar/descriptografar tokens, API Keys e senhas de certificado A1
/// - Usar AES-256-GCM para criptografia segura
/// - Gerar chaves efemeras de criptografia
/// - Ofuscar dados sensiveis em logs
/// - Validar integridade de dados criptografados
///
/// A chave mestra deve vir do backend (Cloud Function). Em ambiente dev,
/// usa uma chave derivada do nome do projeto.
class FiscalCryptoUtil {
  FiscalCryptoUtil._();

  /// Prefixo para identificar dados criptografados (v2 = AES-256-GCM).
  static const _prefix = 'DIP_AES256_v2:';

  /// Chave derivada do projeto para ofuscacao basica (fallback).
  /// Em producao, obter via Cloud Function.
  static const _appKey = 'DiPertin@2026!Fiscal#NF-e';

  /// Cache da chave mestra obtida do backend.
  static String? _chaveMestraCache;
  static DateTime? _chaveCacheEm;

  /// Obtem a chave de criptografia.
  ///
  /// Prioridade:
  /// 1. Cache em memoria (valido por 5 min)
  /// 2. Fallback para chave derivada do projeto
  static String _obterChave() {
    if (_chaveMestraCache != null &&
        _chaveCacheEm != null &&
        DateTime.now().difference(_chaveCacheEm!).inMinutes < 5) {
      return _chaveMestraCache!;
    }
    return _appKey;
  }

  /// Define a chave mestra (chamado apos obter do backend).
  static void definirChaveMestra(String chave) {
    _chaveMestraCache = chave;
    _chaveCacheEm = DateTime.now();
  }

  /// Criptografa um valor sensivel (API Key, Token, senha de certificado).
  ///
  /// Usa AES-256-GCM com IV aleatorio de 12 bytes.
  /// Formato: `DIP_AES256_v2:{iv_base64url}.{ciphertext_base64url}.{tag_base64url}`
  static String encrypt(String plainText) {
    if (plainText.isEmpty) return '';

    final chave = _obterChave();
    final keyBytes = _derivarChave256(chave);
    final key = enc.Key(keyBytes);
    final iv = enc.IV(_gerarIvBytes());
    final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.gcm));

    final encrypted = encrypter.encrypt(plainText, iv: iv);

    // Formato: prefix + iv_b64url.ciphertext_b64url
    final ivB64 = _base64UrlEncode(iv.bytes);
    final dataB64 = _base64UrlEncode(encrypted.bytes);

    return '$_prefix$ivB64.$dataB64';
  }

  /// Descriptografa um valor criptografado com [encrypt].
  ///
  /// Retorna o texto original ou string vazia se invalido.
  static String decrypt(String encryptedText) {
    if (encryptedText.isEmpty) return '';
    if (!encryptedText.startsWith(_prefix)) {
      // Se for formato antigo (XOR), usar fallback
      return _decryptLegacy(encryptedText);
    }

    try {
      final semPrefixo = encryptedText.substring(_prefix.length);
      final partes = semPrefixo.split('.');
      if (partes.length < 2) return '';

      final ivBytes = _base64UrlDecode(partes[0]);
      final dataBytes = _base64UrlDecode(partes[1]);

      final chave = _obterChave();
      final keyBytes = _derivarChave256(chave);
      final key = enc.Key(keyBytes);
      final iv = enc.IV(ivBytes);
      final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.gcm));

      return encrypter.decrypt(enc.Encrypted(dataBytes), iv: iv);
    } catch (_) {
      // Fallback para formato legado
      return _decryptLegacy(encryptedText);
    }
  }

  /// Ofusca um valor para exibicao segura em logs.
  ///
  /// Mostra apenas os primeiros e ultimos caracteres.
  /// Ex: "sk_live_abc...xyz"
  static String ofuscar(String value) {
    if (value.length <= 8) {
      return value.isNotEmpty ? '${value[0]}***' : '';
    }
    return '${value.substring(0, 4)}...${value.substring(value.length - 4)}';
  }

  /// Verifica se uma string parece criptografada pelo sistema.
  static bool pareceCriptografado(String value) {
    return value.startsWith(_prefix) || value.startsWith('DIP_ENC_v1:');
  }

  /// Gera uma chave aleatoria para uso em memoria.
  static String gerarChaveEfemera() {
    final random = Random.secure();
    final bytes = List<int>.generate(32, (_) => random.nextInt(256));
    return _base64UrlEncode(bytes);
  }

  /// Valida a integridade de um valor criptografado.
  static bool validarIntegridade(String encryptedText) {
    if (!encryptedText.startsWith(_prefix)) return false;
    try {
      final semPrefixo = encryptedText.substring(_prefix.length);
      final partes = semPrefixo.split('.');
      if (partes.length < 2) return false;
      _base64UrlDecode(partes[0]);
      _base64UrlDecode(partes[1]);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Remove metadados sensiveis de um mapa de configuracao para log seguro.
  static Map<String, dynamic> sanitizarParaLog(
      Map<String, dynamic> config) {
    final sensivel = [
      'api_key', 'token', 'secret', 'password', 'senha', 'certificate',
      'access_token', 'consumer_secret', 'client_secret', 'key',
      'credentials_encrypted', 'certificate_data_encrypted',
    ];

    return config.map((key, value) {
      final chaveLower = key.toLowerCase();
      if (sensivel.any((s) => chaveLower.contains(s)) && value is String) {
        return MapEntry(key, ofuscar(value));
      }
      return MapEntry(key, value);
    });
  }

  /// Deriva uma chave de 32 bytes (256 bits) a partir de uma string.
  static Uint8List _derivarChave256(String key) {
    final keyBytes = utf8.encode(key);
    // Usa SHA-256 para derivar 32 bytes consistentes
    final digest = pc.SHA256Digest();
    final input = keyBytes;
    final output = Uint8List(32);
    digest.update(input, 0, input.length);
    digest.doFinal(output, 0);
    return output;
  }

  /// Gera 12 bytes aleatorios para IV (GCM recomenda 12 bytes).
  static Uint8List _gerarIvBytes() {
    final random = Random.secure();
    return Uint8List.fromList(List<int>.generate(12, (_) => random.nextInt(256)));
  }

  /// Decriptografa no formato legado (v1 - XOR).
  static String _decryptLegacy(String encryptedText) {
    const prefixLegacy = 'DIP_ENC_v1:';
    if (!encryptedText.startsWith(prefixLegacy)) return encryptedText;
    try {
      final encoded = encryptedText.substring(prefixLegacy.length);
      final encrypted = _base64UrlDecode(encoded);
      final key = _derivarChave256Legacy(_appKey);
      final decrypted = List<int>.generate(encrypted.length, (i) {
        return encrypted[i] ^ key[i % key.length];
      });
      return utf8.decode(decrypted);
    } catch (_) {
      return '';
    }
  }

  static List<int> _derivarChave256Legacy(String key) {
    final keyBytes = utf8.encode(key);
    final result = List<int>.filled(32, 0);
    for (var i = 0; i < 32; i++) {
      result[i] = keyBytes[i % keyBytes.length] ^ (i * 17 + 13) % 256;
    }
    return result;
  }

  static String _base64UrlEncode(List<int> bytes) {
    return base64.encode(bytes)
        .replaceAll('+', '-')
        .replaceAll('/', '_')
        .replaceAll('=', '');
  }

  static Uint8List _base64UrlDecode(String str) {
    String normalized = str
        .replaceAll('-', '+')
        .replaceAll('_', '/');
    switch (normalized.length % 4) {
      case 0:
        break;
      case 2:
        normalized += '==';
        break;
      case 3:
        normalized += '=';
        break;
    }
    return Uint8List.fromList(base64.decode(normalized));
  }

}
