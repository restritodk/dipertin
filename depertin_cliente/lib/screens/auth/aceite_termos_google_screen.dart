// Arquivo: lib/screens/auth/aceite_termos_google_screen.dart

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../auth/google_auth_helper.dart';
import 'widgets/termos_aceite_cadastro.dart';

const Color _diPertinRoxo = Color(0xFF6A1B9A);
const Color _diPertinLaranja = Color(0xFFFF8F00);
const Color _fundoTela = Color(0xFFF5F4F8);

/// Tela obrigatória para novos usuários Google aceitarem termos antes de gravar o perfil.
class AceiteTermosGoogleScreen extends StatefulWidget {
  const AceiteTermosGoogleScreen({super.key});

  @override
  State<AceiteTermosGoogleScreen> createState() => _AceiteTermosGoogleScreenState();
}

class _AceiteTermosGoogleScreenState extends State<AceiteTermosGoogleScreen> {
  bool _aceito = false;
  bool _processando = false;

  Future<void> _cancelar() async {
    if (_processando) return;
    setState(() => _processando = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        await user.delete();
      }
    } catch (e) {
      debugPrint('AceiteTermosGoogle cancelar delete: $e');
    }
    try {
      await signOutGoogle();
    } catch (_) {}
    try {
      await FirebaseAuth.instance.signOut();
    } catch (_) {}
    if (!mounted) return;
    Navigator.of(context).pop(false);
  }

  void _confirmar() {
    if (!_aceito) return;
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, dynamic result) async {
        if (didPop) return;
        await _cancelar();
      },
      child: Scaffold(
      backgroundColor: _fundoTela,
      appBar: AppBar(
        title: const Text(
          'Termos e privacidade',
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
        leading: _processando
            ? const SizedBox(width: 48)
            : IconButton(
                icon: const Icon(Icons.close_rounded),
                onPressed: _cancelar,
              ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFE8E6ED)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.person_add_alt_1_rounded,
                        color: _diPertinRoxo, size: 36),
                    const SizedBox(height: 12),
                    Text(
                      'Concluir cadastro',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: Colors.grey.shade900,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Para criar sua conta no DiPertin com o Google, é '
                      'necessário ler e aceitar os Termos de Uso e a Política '
                      'de Privacidade. Toque nos links abaixo para abrir os '
                      'documentos.',
                      style: TextStyle(
                        fontSize: 14.5,
                        height: 1.5,
                        color: Colors.grey.shade800,
                      ),
                    ),
                    const SizedBox(height: 18),
                    TermosAceiteCadastroWidget(
                      aceito: _aceito,
                      onChanged: (v) => setState(() => _aceito = v),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              FilledButton(
                onPressed: (_processando || !_aceito) ? null : _confirmar,
                style: FilledButton.styleFrom(
                  backgroundColor: _diPertinLaranja,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: _diPertinLaranja.withValues(alpha: 0.45),
                  minimumSize: const Size(double.infinity, 52),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: _processando
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2.5,
                        ),
                      )
                    : const Text(
                        'Aceitar e continuar',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
              ),
              const SizedBox(height: 10),
              TextButton(
                onPressed: _processando ? null : _cancelar,
                child: Text(
                  'Cancelar cadastro',
                  style: TextStyle(
                    color: Colors.red.shade700,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
    );
  }
}
