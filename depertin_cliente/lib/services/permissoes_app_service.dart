// ignore_for_file: public_member_api_docs

import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

import 'package:depertin_cliente/services/android_nav_intent.dart';

/// Resultado de [PermissoesAppService.garantirCamera], [garantirGaleriaFotos], etc.
enum ResultadoPermissao {
  concedida,
  negada,
  negadaPermanentemente,
}

/// Resultado de [PermissoesAppService.garantirLocalizacao].
enum ResultadoLocalizacao {
  ok,
  servicoDesativado,
  negada,
  negadaPermanentemente,
}

/// Solicita e valida permissões de forma alinhada ao Android (API recentes) e iOS.
class PermissoesAppService {
  PermissoesAppService._();

  static Future<int?> _androidSdk() async {
    if (kIsWeb || !Platform.isAndroid) return null;
    return (await DeviceInfoPlugin().androidInfo).version.sdkInt;
  }

  static ResultadoPermissao _mapearStatus(PermissionStatus s) {
    if (s.isGranted || s.isLimited || s.isProvisional) {
      return ResultadoPermissao.concedida;
    }
    if (s.isPermanentlyDenied) {
      return ResultadoPermissao.negadaPermanentemente;
    }
    return ResultadoPermissao.negada;
  }

  /// Câmera (foto perfil, etc.).
  static Future<ResultadoPermissao> garantirCamera() async {
    if (kIsWeb) return ResultadoPermissao.concedida;
    final status = await Permission.camera.request();
    return _mapearStatus(status);
  }

  /// Galeria / fotos (ImagePicker com galeria).
  ///
  /// Android 13+ (API 33): solicita `READ_MEDIA_IMAGES` (Permission.photos).
  /// Android 12 e anteriores: solicita leitura de armazenamento.
  static Future<ResultadoPermissao> garantirGaleriaFotos() async {
    if (kIsWeb) return ResultadoPermissao.concedida;
    if (Platform.isIOS) {
      return _mapearStatus(await Permission.photos.request());
    }
    if (Platform.isAndroid) {
      final sdk = await _androidSdk();
      if (sdk != null && sdk >= 33) {
        return _mapearStatus(await Permission.photos.request());
      }
      return _mapearStatus(await Permission.storage.request());
    }
    return ResultadoPermissao.concedida;
  }

  /// Android &lt; 13: leitura para anexos (FilePicker em alguns aparelhos).
  /// Android 13+ (SAF): em geral não exige; retorna [concedida].
  static Future<ResultadoPermissao> garantirLeituraArquivosAnexos() async {
    if (kIsWeb || !Platform.isAndroid) {
      return ResultadoPermissao.concedida;
    }
    final sdk = await _androidSdk();
    if (sdk == null || sdk >= 33) {
      return ResultadoPermissao.concedida;
    }
    return _mapearStatus(await Permission.storage.request());
  }

  /// Localização (Geolocator): serviço ligado + permissão runtime.
  static Future<ResultadoLocalizacao> garantirLocalizacao() async {
    final servico = await Geolocator.isLocationServiceEnabled();
    if (!servico) return ResultadoLocalizacao.servicoDesativado;

    var p = await Geolocator.checkPermission();
    if (p == LocationPermission.denied) {
      p = await Geolocator.requestPermission();
    }
    if (p == LocationPermission.denied) {
      return ResultadoLocalizacao.negada;
    }
    if (p == LocationPermission.deniedForever) {
      return ResultadoLocalizacao.negadaPermanentemente;
    }
    return ResultadoLocalizacao.ok;
  }

  /// Notificações push (Android 13+ — POST_NOTIFICATIONS).
  static Future<ResultadoPermissao> garantirNotificacoesAndroid() async {
    if (kIsWeb || !Platform.isAndroid) {
      return ResultadoPermissao.concedida;
    }
    final sdk = await _androidSdk();
    if (sdk == null || sdk < 33) {
      return ResultadoPermissao.concedida;
    }
    return _mapearStatus(await Permission.notification.request());
  }

  /// Exibir sobre outros apps (overlay / SYSTEM_ALERT_WINDOW).
  /// Retorna `true` se a permissão já está concedida.
  static Future<bool> verificarOverlay() async {
    if (kIsWeb || !Platform.isAndroid) return true;
    return AndroidNavIntent.canDrawOverlays();
  }
}

/// Mensagens e diálogos padronizados (negado / negado permanentemente / GPS desligado).
class PermissoesFeedback {
  PermissoesFeedback._();

  static const Color _roxo = Color(0xFF6A1B9A);

  static void _snack(
    BuildContext context, {
    required String mensagem,
    Color? cor,
  }) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(mensagem),
        backgroundColor: cor ?? Colors.grey.shade800,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  static Future<void> _dialogConfigApp(
    BuildContext context, {
    required String titulo,
    required String texto,
  }) async {
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          titulo,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        content: Text(texto, style: const TextStyle(height: 1.4)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Fechar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: _roxo,
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              await openAppSettings();
            },
            child: const Text('Abrir configurações'),
          ),
        ],
      ),
    );
  }

  static Future<void> _dialogServicoLocalizacao(BuildContext context) async {
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Localização desligada',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        content: const Text(
          'O GPS do aparelho está desativado. Ative a localização nas '
          'configurações do sistema para preencher o endereço automaticamente.',
          style: TextStyle(height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Fechar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: _roxo,
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              await Geolocator.openLocationSettings();
            },
            child: const Text('Abrir localização'),
          ),
        ],
      ),
    );
  }

  static void camera(BuildContext context, ResultadoPermissao r) {
    switch (r) {
      case ResultadoPermissao.concedida:
        return;
      case ResultadoPermissao.negada:
        _snack(
          context,
          mensagem:
              'Permissão da câmera não foi concedida. '
              'Conceda a permissão para tirar a foto.',
          cor: Colors.orange.shade800,
        );
        return;
      case ResultadoPermissao.negadaPermanentemente:
        Future<void>.microtask(() async {
          if (!context.mounted) return;
          await _dialogConfigApp(
            context,
            titulo: 'Permissão da câmera',
            texto:
                'Para usar a câmera no DiPertin, ative a permissão em '
                'Configurações → Apps → DiPertin → Permissões → Câmera.',
          );
        });
        return;
    }
  }

  static void galeria(BuildContext context, ResultadoPermissao r) {
    switch (r) {
      case ResultadoPermissao.concedida:
        return;
      case ResultadoPermissao.negada:
        _snack(
          context,
          mensagem:
              'Permissão para acessar fotos não foi concedida. '
              'Conceda o acesso para escolher uma imagem da galeria.',
          cor: Colors.orange.shade800,
        );
        return;
      case ResultadoPermissao.negadaPermanentemente:
        Future<void>.microtask(() async {
          if (!context.mounted) return;
          await _dialogConfigApp(
            context,
            titulo: 'Acesso às fotos',
            texto:
                'Para escolher imagens da galeria, ative o acesso a fotos e '
                'arquivos em Configurações → Apps → DiPertin → Permissões.',
          );
        });
        return;
    }
  }

  static void arquivosAnexos(BuildContext context, ResultadoPermissao r) {
    switch (r) {
      case ResultadoPermissao.concedida:
        return;
      case ResultadoPermissao.negada:
        _snack(
          context,
          mensagem:
              'Permissão de armazenamento não foi concedida. '
              'Ela é necessária para anexar documentos neste dispositivo.',
          cor: Colors.orange.shade800,
        );
        return;
      case ResultadoPermissao.negadaPermanentemente:
        Future<void>.microtask(() async {
          if (!context.mounted) return;
          await _dialogConfigApp(
            context,
            titulo: 'Acesso a arquivos',
            texto:
                'Para anexar documentos, ative o armazenamento ou arquivos em '
                'Configurações → Apps → DiPertin → Permissões.',
          );
        });
        return;
    }
  }

  static Future<void> localizacao(
    BuildContext context,
    ResultadoLocalizacao r,
  ) async {
    switch (r) {
      case ResultadoLocalizacao.ok:
        return;
      case ResultadoLocalizacao.servicoDesativado:
        await _dialogServicoLocalizacao(context);
        return;
      case ResultadoLocalizacao.negada:
        _snack(
          context,
          mensagem:
              'Permissão de localização não foi concedida. '
              'Você pode informar o endereço manualmente.',
          cor: Colors.orange.shade800,
        );
        return;
      case ResultadoLocalizacao.negadaPermanentemente:
        await _dialogConfigApp(
          context,
          titulo: 'Permissão de localização',
          texto:
              'Para usar o GPS, ative a localização em '
              'Configurações → Apps → DiPertin → Permissões → Localização.',
        );
        return;
    }
  }

  static void notificacoes(BuildContext context, ResultadoPermissao r) {
    switch (r) {
      case ResultadoPermissao.concedida:
        return;
      case ResultadoPermissao.negada:
        _snack(
          context,
          mensagem:
              'Notificações não foram ativadas. Você pode ativar depois '
              'nas configurações do app para receber alertas de pedidos.',
          cor: Colors.orange.shade800,
        );
        return;
      case ResultadoPermissao.negadaPermanentemente:
        Future<void>.microtask(() async {
          if (!context.mounted) return;
          await _dialogConfigApp(
            context,
            titulo: 'Notificações',
            texto:
                'Para receber alertas do DiPertin, ative as notificações em '
                'Configurações → Apps → DiPertin → Notificações.',
          );
        });
        return;
    }
  }

  /// Fluxo completo de overlay: verifica, exibe bottom sheet se necessário,
  /// envia para configurações e revalida ao retornar.
  ///
  /// Retorna `true` se a permissão está concedida ao final do fluxo.
  static Future<bool> verificarEGarantirOverlay(BuildContext context) async {
    if (kIsWeb || !Platform.isAndroid) return true;

    final jaPermitido = await AndroidNavIntent.canDrawOverlays();
    if (jaPermitido) return true;

    if (!context.mounted) return false;

    final aceitou = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => const _OverlayPermissaoSheet(),
    );

    if (aceitou != true) return false;

    await AndroidNavIntent.openOverlayPermissionSettings();

    await Future<void>.delayed(const Duration(milliseconds: 800));

    final concedido = await AndroidNavIntent.canDrawOverlays();
    if (!context.mounted) return concedido;

    if (concedido) {
      _snack(
        context,
        mensagem: 'Permissão concedida! O recurso de overlay está ativo.',
        cor: Colors.green.shade700,
      );
    } else {
      _snack(
        context,
        mensagem:
            'A permissão ainda não foi ativada. '
            'Você pode ativar depois no diagnóstico de alertas.',
        cor: Colors.orange.shade800,
      );
    }

    return concedido;
  }
}

class _OverlayPermissaoSheet extends StatelessWidget {
  const _OverlayPermissaoSheet();

  static const _roxo = Color(0xFF6A1B9A);

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 24),
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: _roxo.withAlpha(25),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.layers, size: 34, color: _roxo),
          ),
          const SizedBox(height: 20),
          const Text(
            'Exibir sobre outros apps',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: Color(0xFF1A1A2E),
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          const Text(
            'Para exibir alertas de novas corridas mesmo quando o app '
            'estiver em segundo plano, é necessário permitir a opção '
            '"Exibir sobre outros apps".',
            style: TextStyle(
              fontSize: 14,
              color: Color(0xFF555555),
              height: 1.5,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          const Text(
            'Essa permissão é usada por apps como 99, Uber e iFood '
            'para mostrar o botão flutuante de corridas.',
            style: TextStyle(
              fontSize: 13,
              color: Color(0xFF888888),
              height: 1.4,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 28),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: FilledButton.icon(
              onPressed: () => Navigator.pop(context, true),
              style: FilledButton.styleFrom(
                backgroundColor: _roxo,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                textStyle: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              icon: const Icon(Icons.settings, size: 20),
              label: const Text('Permitir agora'),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: TextButton(
              onPressed: () => Navigator.pop(context, false),
              style: TextButton.styleFrom(
                foregroundColor: Colors.grey.shade600,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                textStyle: const TextStyle(fontSize: 14),
              ),
              child: const Text('Agora não'),
            ),
          ),
        ],
      ),
    );
  }
}
