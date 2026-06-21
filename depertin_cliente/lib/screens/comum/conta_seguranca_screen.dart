// Arquivo: lib/screens/comum/conta_seguranca_screen.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'package:depertin_cliente/screens/comum/alterar_senha_screen.dart';
import 'package:depertin_cliente/screens/comum/edit_profile_screen.dart';

import '../../services/biometria_service.dart';
import '../../widgets/dipertin_scroll_body.dart';
import '../../utils/safe_area_insets.dart' show diPertinScrollPaddingInner;

const Color _diPertinRoxo = Color(0xFF6A1B9A);
const Color _diPertinLaranja = Color(0xFFFF8F00);
const Color _fundoTela = Color(0xFFF5F4F8);

/// Submenu de Configurações: conta e segurança.
class ContaSegurancaScreen extends StatefulWidget {
  const ContaSegurancaScreen({super.key});

  @override
  State<ContaSegurancaScreen> createState() => _ContaSegurancaScreenState();
}

class _ContaSegurancaScreenState extends State<ContaSegurancaScreen> {
  bool _biometriaAtiva = false;
  BiometriaDisponibilidade? _disp;
  bool _carregandoBiometria = true;
  bool _togglePendente = false;

  @override
  void initState() {
    super.initState();
    _carregarEstadoBiometria();
  }

  Future<void> _carregarEstadoBiometria() async {
    final bio = BiometriaService.instancia;
    final disp = await bio.consultarDisponibilidade(forcarRefresh: true);
    final ativa = await bio.estaAtivada();
    if (!mounted) return;
    setState(() {
      _disp = disp;
      _biometriaAtiva = ativa;
      _carregandoBiometria = false;
    });
  }

  Future<void> _toggleBiometria(bool ligar) async {
    if (_togglePendente) return;
    setState(() => _togglePendente = true);
    try {
      final bio = BiometriaService.instancia;
      if (ligar) {
        final user = FirebaseAuth.instance.currentUser;
        if (user == null) {
          _snack(
            'Faça login novamente antes de ativar a digital.',
            Colors.orange,
          );
          return;
        }

        final disp = await bio.consultarDisponibilidade(forcarRefresh: true);
        if (!disp.disponivelParaUso) {
          _snack(
            'Seu aparelho não tem biometria cadastrada. Configure a digital '
            'nas opções do sistema e tente novamente.',
            Colors.orange,
          );
          return;
        }

        // Para ativar manualmente com conta existente, precisamos do método.
        // Se a conta tem provider "password", perguntar a senha não é prático
        // aqui (evita UX de redigitar), então orientamos o usuário a ativar
        // a biometria logo após um login normal. Para contas Google,
        // gravamos direto.
        final ehGoogle = user.providerData.any((p) => p.providerId == 'google.com');
        final temSenha = user.providerData.any((p) => p.providerId == 'password');

        if (ehGoogle && !temSenha) {
          final resultado = await bio.autenticarComBiometria(
            razao:
                'Confirme sua digital para ativar o acesso rápido no DiPertin.',
          );
          if (resultado != BiometriaResultado.sucesso) {
            _tratarResultadoNaoSucesso(resultado);
            return;
          }
          await bio.ativarParaConta(
            uid: user.uid,
            email: user.email ?? '',
            metodo: BiometriaMetodoLogin.google,
          );
          _snack('Digital ativada com sucesso.', Colors.green);
          if (mounted) setState(() => _biometriaAtiva = true);
          return;
        }

        // Conta com senha → abrir modal premium pedindo a senha atual.
        final senha = await _pedirSenhaAtual();
        if (senha == null || senha.isEmpty) return;

        // Reautentica para confirmar que a senha está correta antes de
        // persistir no secure storage.
        try {
          final cred = EmailAuthProvider.credential(
            email: user.email ?? '',
            password: senha,
          );
          await user.reauthenticateWithCredential(cred);
        } on FirebaseAuthException catch (e) {
          _snack(
            e.code == 'wrong-password' || e.code == 'invalid-credential'
                ? 'Senha incorreta.'
                : 'Não foi possível validar sua senha: ${e.code}',
            Colors.red,
          );
          return;
        }

        final resultado = await bio.autenticarComBiometria(
          razao:
              'Confirme sua digital para ativar o acesso rápido no DiPertin.',
        );
        if (resultado != BiometriaResultado.sucesso) {
          _tratarResultadoNaoSucesso(resultado);
          return;
        }

        await bio.ativarParaConta(
          uid: user.uid,
          email: user.email ?? '',
          metodo: BiometriaMetodoLogin.emailSenha,
          senhaEmTextoPuro: senha,
        );
        _snack('Digital ativada com sucesso.', Colors.green);
        if (mounted) setState(() => _biometriaAtiva = true);
      } else {
        final ok = await _confirmarDesativar();
        if (ok != true) return;
        await bio.desativar();
        _snack('Acesso por digital desativado.', Colors.grey);
        if (mounted) setState(() => _biometriaAtiva = false);
      }
    } finally {
      if (mounted) setState(() => _togglePendente = false);
    }
  }

  void _tratarResultadoNaoSucesso(BiometriaResultado r) {
    switch (r) {
      case BiometriaResultado.cancelado:
        return;
      case BiometriaResultado.indisponivel:
        _snack(
          'Biometria indisponível. Cadastre uma digital no aparelho.',
          Colors.orange,
        );
        break;
      case BiometriaResultado.falhou:
        _snack(
          'Digital não reconhecida. Tente novamente.',
          Colors.red,
        );
        break;
      case BiometriaResultado.erro:
        _snack(
          'Não foi possível ativar agora. Tente novamente.',
          Colors.red,
        );
        break;
      case BiometriaResultado.sucesso:
        break;
    }
  }

  Future<String?> _pedirSenhaAtual() async {
    final ctrl = TextEditingController();
    bool oculta = true;
    final resultado = await showDialog<String?>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) {
          return Dialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(22, 24, 22, 18),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: _diPertinRoxo.withValues(alpha: 0.12),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.fingerprint_rounded,
                          color: _diPertinRoxo,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          'Confirme sua senha',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF1A1A2E),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Para vincular sua digital a esta conta, digite sua senha atual. Ela fica apenas neste aparelho de forma criptografada.',
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.45,
                      color: Colors.grey.shade700,
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: ctrl,
                    obscureText: oculta,
                    decoration: InputDecoration(
                      labelText: 'Senha atual',
                      filled: true,
                      fillColor: const Color(0xFFF7F6FB),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide:
                            const BorderSide(color: Color(0xFFE0DEE8)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide:
                            const BorderSide(color: Color(0xFFE0DEE8)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(
                          color: _diPertinLaranja,
                          width: 2,
                        ),
                      ),
                      suffixIcon: IconButton(
                        icon: Icon(
                          oculta
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                          color: _diPertinRoxo.withValues(alpha: 0.75),
                        ),
                        onPressed: () => setSt(() => oculta = !oculta),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.of(ctx).pop(null),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.grey.shade800,
                            padding:
                                const EdgeInsets.symmetric(vertical: 13),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text(
                            'Cancelar',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton(
                          onPressed: () =>
                              Navigator.of(ctx).pop(ctrl.text.trim()),
                          style: FilledButton.styleFrom(
                            backgroundColor: _diPertinLaranja,
                            foregroundColor: Colors.white,
                            padding:
                                const EdgeInsets.symmetric(vertical: 13),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text(
                            'Confirmar',
                            style: TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
    return resultado;
  }

  Future<bool?> _confirmarDesativar() async {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text(
          'Desativar acesso por digital?',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        content: const Text(
          'Você precisará entrar novamente com e-mail e senha (ou Google) '
          'e poderá reativar a digital quando quiser.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: _diPertinRoxo,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Desativar'),
          ),
        ],
      ),
    );
  }

  void _snack(String msg, Color cor) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: cor,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final User? user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      backgroundColor: _fundoTela,
      appBar: AppBar(
        title: const Text(
          'Conta e segurança',
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
      body: user == null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Faça login para gerenciar sua conta.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey.shade700, height: 1.4),
                ),
              ),
            )
          : StreamBuilder<DocumentSnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('users')
                  .doc(user.uid)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting &&
                    !snapshot.hasData) {
                  return const Center(
                    child: CircularProgressIndicator(color: _diPertinRoxo),
                  );
                }
                if (!snapshot.hasData || !snapshot.data!.exists) {
                  return Center(
                    child: Text(
                      'Não foi possível carregar seus dados.',
                      style: TextStyle(color: Colors.grey.shade700),
                    ),
                  );
                }

                final Map<String, dynamic> d =
                    snapshot.data!.data() as Map<String, dynamic>;
                final String nome = d['nome']?.toString() ?? '';
                final String endereco = d['endereco_padrao']?.toString() ?? '';
                final String? role = d['role']?.toString();
                final String lojaNome = d['loja_nome']?.toString() ?? '';
                return DiPertinScrollBody(
                  padding: diPertinScrollPaddingInner(
                    context,
                    extraBottom: 24,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Conta e segurança',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: Colors.grey.shade800,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Gerencie seus dados e acesso ao app.',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey.shade600,
                          height: 1.45,
                        ),
                      ),
                      const SizedBox(height: 18),
                      _cardMenu(
                        children: [
                          _itemMenu(
                            icon: Icons.person_outline_rounded,
                            cor: _diPertinRoxo,
                            titulo: 'Editar perfil',
                            subtitulo: 'Nome, foto e dados pessoais',
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => EditProfileScreen(
                                    nomeAtual: nome,
                                    enderecoAtual: endereco,
                                    role: role,
                                    nomeLojaAtual:
                                        lojaNome.isEmpty ? null : lojaNome,
                                  ),
                                ),
                              );
                            },
                          ),
                          Divider(height: 1, color: Colors.grey.shade200),
                          _itemMenu(
                            icon: Icons.lock_outline_rounded,
                            cor: _diPertinLaranja,
                            titulo: 'Alterar senha',
                            subtitulo: 'Senha atual e nova senha',
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) =>
                                      const AlterarSenhaScreen(),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      _secaoBiometria(),
                    ],
                  ),
                );
              },
            ),
    );
  }

  Widget _secaoBiometria() {
    if (_carregandoBiometria) {
      return const SizedBox.shrink();
    }
    final suporta = _disp?.dispositivoSuporta ?? false;

    if (!suporta) {
      // Aparelho não suporta biometria → mostra card informativo discreto.
      return _cardMenu(
        children: [
          ListTile(
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            leading: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.grey.shade200,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.fingerprint_rounded,
                color: Colors.grey.shade500,
                size: 22,
              ),
            ),
            title: const Text(
              'Acesso por Digital',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 15,
                color: Color(0xFF1A1A2E),
              ),
            ),
            subtitle: Text(
              'Este aparelho não suporta biometria.',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
          ),
        ],
      );
    }

    final semBiometriaCadastrada =
        !(_disp?.algumaBiometriaCadastrada ?? false);

    return _cardMenu(
      children: [
        SwitchListTile.adaptive(
          value: _biometriaAtiva,
          onChanged: (_togglePendente || semBiometriaCadastrada)
              ? null
              : _toggleBiometria,
          activeThumbColor: _diPertinLaranja,
          activeTrackColor: _diPertinLaranja.withValues(alpha: 0.4),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          secondary: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: _diPertinRoxo.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.fingerprint_rounded,
              color: _diPertinRoxo,
              size: 22,
            ),
          ),
          title: const Text(
            'Acesso por Digital',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 15,
              color: Color(0xFF1A1A2E),
            ),
          ),
          subtitle: Text(
            semBiometriaCadastrada
                ? 'Cadastre uma digital nas configurações do aparelho.'
                : _biometriaAtiva
                    ? 'Ativo neste aparelho — você pode entrar só com a digital.'
                    : 'Entre com uma simples leitura da sua digital.',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
        ),
        if (_togglePendente)
          const Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: Center(
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  color: _diPertinRoxo,
                  strokeWidth: 2.2,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _cardMenu({required List<Widget> children}) {
    return Container(
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
      child: Column(children: children),
    );
  }

  Widget _itemMenu({
    required IconData icon,
    required Color cor,
    required String titulo,
    required String subtitulo,
    required VoidCallback onTap,
  }) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: cor.withValues(alpha: 0.12),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: cor, size: 22),
      ),
      title: Text(
        titulo,
        style: const TextStyle(
          fontWeight: FontWeight.w700,
          fontSize: 15,
          color: Color(0xFF1A1A2E),
        ),
      ),
      subtitle: Text(
        subtitulo,
        style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
      ),
      trailing: Icon(Icons.chevron_right_rounded, color: Colors.grey.shade400),
      onTap: onTap,
    );
  }
}
