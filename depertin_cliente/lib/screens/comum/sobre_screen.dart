// Arquivo: lib/screens/comum/sobre_screen.dart

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

const Color _diPertinRoxo = Color(0xFF6A1B9A);
const Color _diPertinLaranja = Color(0xFFFF8F00);
const Color _fundoTela = Color(0xFFF5F4F8);

/// Informações do aplicativo DiPertin (versão, descrição).
class SobreScreen extends StatefulWidget {
  const SobreScreen({super.key});

  @override
  State<SobreScreen> createState() => _SobreScreenState();
}

class _SobreScreenState extends State<SobreScreen> {
  PackageInfo? _info;
  Object? _erro;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (!mounted) return;
      setState(() {
        _info = info;
        _erro = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _erro = e;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _fundoTela,
      appBar: AppBar(
        title: const Text(
          'Sobre',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            letterSpacing: -0.2,
          ),
        ),
        backgroundColor: _diPertinRoxo,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
        child: Column(
          children: [
            Center(
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 20,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Image.asset(
                  'assets/logo.png',
                  height: 96,
                  errorBuilder: (context, error, stackTrace) => Icon(
                    Icons.storefront_rounded,
                    size: 72,
                    color: _diPertinLaranja,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'DiPertin',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w800,
                color: Color(0xFF1A1A2E),
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'O que você precisa, bem aqui!',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: _diPertinRoxo.withValues(alpha: 0.95),
              ),
            ),
            const SizedBox(height: 20),
            _card(
              child: _linhaInfo(
                icon: Icons.smartphone_rounded,
                titulo: 'Versão',
                valor: _textoVersao(),
              ),
            ),
            const SizedBox(height: 16),
            _card(
              child: Column(
                children: [
                  _linhaInfo(
                    icon: Icons.badge_rounded,
                    titulo: 'CNPJ',
                    valor: '66.040.998/0001-66',
                  ),
                  const Divider(height: 22, color: Color(0xFFEDEAF2)),
                  _linhaInfo(
                    icon: Icons.phone_rounded,
                    titulo: 'Telefone',
                    valor: '(66) 3180-0107',
                    onTap: _abrirTelefone,
                    destaque: true,
                  ),
                  const Divider(height: 22, color: Color(0xFFEDEAF2)),
                  _linhaInfo(
                    icon: Icons.language_rounded,
                    titulo: 'Site',
                    valor: 'www.dipertin.com.br',
                    onTap: _abrirSite,
                    destaque: true,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _card(
              child: Text(
                'O DiPertin é um marketplace local que conecta clientes, '
                'lojas parceiras e entregadores. Compre em diversas lojas da '
                'sua cidade, acompanhe seus pedidos, converse com o suporte '
                'e gerencie seu perfil em um só lugar.',
                style: TextStyle(
                  fontSize: 14.5,
                  height: 1.55,
                  color: Colors.grey.shade800,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              '© ${DateTime.now().year} DiPertin',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12.5,
                color: Colors.grey.shade600,
              ),
            ),
            if (_erro != null) ...[
              const SizedBox(height: 12),
              Text(
                'Não foi possível carregar a versão automaticamente.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _textoVersao() {
    if (_info != null) {
      return _info!.version;
    }
    if (_erro != null) {
      return '1.0.0';
    }
    return '…';
  }

  Widget _card({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE8E6ED)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _linhaInfo({
    required IconData icon,
    required String titulo,
    required String valor,
    VoidCallback? onTap,
    bool destaque = false,
  }) {
    final Color corValor = destaque
        ? _diPertinRoxo
        : const Color(0xFF1A1A2E);
    final valorWidget = Text(
      valor,
      style: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w700,
        color: corValor,
        decoration: onTap != null ? TextDecoration.underline : null,
        decorationColor: corValor.withValues(alpha: 0.35),
      ),
    );

    final conteudo = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: _diPertinLaranja, size: 22),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                titulo,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade600,
                ),
              ),
              const SizedBox(height: 4),
              onTap != null
                  ? valorWidget
                  : SelectableText(
                      valor,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1A1A2E),
                      ),
                    ),
            ],
          ),
        ),
        if (onTap != null)
          Icon(
            Icons.open_in_new_rounded,
            size: 18,
            color: _diPertinRoxo.withValues(alpha: 0.7),
          ),
      ],
    );

    if (onTap == null) return conteudo;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: conteudo,
      ),
    );
  }

  Future<void> _abrirTelefone() async {
    final uri = Uri(scheme: 'tel', path: '6631800107');
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
        return;
      }
    } catch (_) {}
    _mostrarErroLink('Não foi possível abrir o discador.');
  }

  Future<void> _abrirSite() async {
    final uri = Uri.parse('https://www.dipertin.com.br');
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        return;
      }
    } catch (_) {}
    _mostrarErroLink('Não foi possível abrir o site.');
  }

  void _mostrarErroLink(String mensagem) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(mensagem),
        backgroundColor: Colors.red,
      ),
    );
  }
}
