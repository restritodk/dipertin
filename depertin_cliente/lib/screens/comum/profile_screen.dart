// Arquivo: lib/screens/comum/profile_screen.dart

import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'package:depertin_cliente/auth/google_auth_helper.dart';
import 'package:depertin_cliente/screens/cliente/chat_suporte_screen.dart';
import 'package:depertin_cliente/screens/comum/configuracoes_screen.dart';
import 'package:depertin_cliente/screens/comum/edit_profile_screen.dart';
import 'package:depertin_cliente/screens/entregador/entregador_home_screen.dart';
import 'package:depertin_cliente/services/conta_bloqueio_entregador_service.dart';
import 'package:depertin_cliente/services/conta_bloqueio_lojista_service.dart';
import 'package:depertin_cliente/services/permissoes_app_service.dart';
import 'package:depertin_cliente/utils/cpf_perfil_usuario.dart';
import 'package:depertin_cliente/widgets/entregador_conta_bloqueada_overlay.dart';
import 'package:depertin_cliente/widgets/lojista_conta_bloqueada_overlay.dart';
import '../auth/login_screen.dart';
import '../cliente/orders_screen.dart';
import '../entregador/entregador_form_screen.dart';
import '../lojista/lojista_dashboard_screen.dart';
import '../lojista/lojista_form_screen.dart';

const Color diPertinRoxo = Color(0xFF6A1B9A);
const Color diPertinLaranja = Color(0xFFFF8F00);

String _rotuloTipoPerfil(String role) {
  switch (role) {
    case 'lojista':
      return 'Lojista';
    case 'entregador':
      return 'Entregador';
    case 'master':
      return 'Administrador';
    case 'master_city':
      return 'Gestor da cidade';
    default:
      return 'Cliente';
  }
}

/// Firestore: `ativo`, `aprovado` ou `aprovada`.
bool _statusLojaAprovada(String s) =>
    s == 'aprovado' || s == 'aprovada' || s == 'ativo';

void _abrirPainelLojistaOuCorrecao(
  BuildContext context,
  Map<String, dynamic> userData,
) {
  if (ContaBloqueioLojistaService.estaBloqueadoParaOperacoes(userData)) {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        insetPadding: EdgeInsets.zero,
        child: SizedBox(
          width: double.infinity,
          height: double.infinity,
          child: LojistaContaBloqueadaOverlay(
            dadosUsuario: userData,
            onSair: () async {
              Navigator.of(ctx).pop();
              await FirebaseAuth.instance.signOut();
            },
          ),
        ),
      ),
    );
    return;
  }
  if (ContaBloqueioLojistaService.lojaRecusadaSomenteCorrecaoCadastro(userData)) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const LojistaFormScreen(),
      ),
    );
    return;
  }
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (context) => const LojistaDashboardScreen(),
    ),
  );
}

void _abrirPainelEntregadorOuCorrecao(
  BuildContext context,
  Map<String, dynamic> userData,
) {
  if (ContaBloqueioEntregadorService.estaBloqueadoParaOperacoes(userData)) {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        insetPadding: EdgeInsets.zero,
        child: SizedBox(
          width: double.infinity,
          height: double.infinity,
          child: EntregadorContaBloqueadaOverlay(
            dadosUsuario: userData,
            onSair: () async {
              Navigator.of(ctx).pop();
              await FirebaseAuth.instance.signOut();
            },
          ),
        ),
      ),
    );
    return;
  }
  final statusEntregador = userData['entregador_status'] ?? 'pendente';
  if (statusEntregador == 'bloqueado') {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const EntregadorFormScreen(),
      ),
    );
    return;
  }
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (context) => const EntregadorHomeScreen(),
    ),
  );
}

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _isUploadingFoto = false;
  String? _statusLojaDono;
  String? _nomeLojaDono;
  String? _ownerUidCache;

  Future<void> _confirmarSair(BuildContext context) async {
    final bool? sair = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.logout_rounded, color: diPertinLaranja),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Sair da conta?',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
        content: const Text(
          'Você precisará entrar de novo para usar o DiPertin.',
          style: TextStyle(height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: diPertinRoxo,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sair'),
          ),
        ],
      ),
    );
    if (sair == true && context.mounted) {
      await signOutGoogle();
      await FirebaseAuth.instance.signOut();
      if (!context.mounted) return;
      Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
        MaterialPageRoute<void>(builder: (_) => const LoginScreen()),
        (route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F4F8),
      appBar: AppBar(
        title: const Text(
          'Meu perfil',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            letterSpacing: -0.2,
          ),
        ),
        backgroundColor: diPertinRoxo,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      body: StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (context, authSnapshot) {
          if (authSnapshot.connectionState == ConnectionState.waiting &&
              !authSnapshot.hasData) {
            return const Center(
              child: CircularProgressIndicator(color: diPertinRoxo),
            );
          }

          if (!authSnapshot.hasData) {
            return _construirTelaSemLogin(context);
          }

          final User user = authSnapshot.data!;

          return StreamBuilder<DocumentSnapshot>(
            stream: FirebaseFirestore.instance
                .collection('users')
                .doc(user.uid)
                .snapshots(),
            builder: (context, userSnapshot) {
              if (userSnapshot.connectionState == ConnectionState.waiting &&
                  !userSnapshot.hasData) {
                return const Center(
                  child: CircularProgressIndicator(color: diPertinRoxo),
                );
              }

              if (userSnapshot.hasError) {
                return _erroCarregarPerfil(context, '${userSnapshot.error}');
              }

              if (!userSnapshot.hasData || !userSnapshot.data!.exists) {
                return _erroPerfilNaoEncontrado(context);
              }

              final Map<String, dynamic> userData =
                  userSnapshot.data!.data() as Map<String, dynamic>;
              final double saldo =
                  (userData['saldo'] ?? 0.0).toDouble();

              return _construirTelaComLogin(
                context,
                user.email ?? '',
                userData,
                saldoCarteira: saldo,
              );
            },
          );
        },
      ),
    );
  }

  Widget _erroPerfilNaoEncontrado(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.person_off_outlined, size: 64, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text(
              'Perfil não encontrado',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: Colors.grey.shade800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Não foi possível carregar seus dados. Tente novamente ou entre em contato com o suporte.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade600, height: 1.4),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () {
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute(builder: (_) => const ProfileScreen()),
                );
              },
              style: FilledButton.styleFrom(
                backgroundColor: diPertinLaranja,
                foregroundColor: Colors.white,
              ),
              icon: const Icon(Icons.refresh),
              label: const Text('Tentar novamente'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _erroCarregarPerfil(BuildContext context, String mensagem) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.cloud_off_outlined, size: 56, color: Colors.orange),
            const SizedBox(height: 16),
            Text(
              'Algo deu errado',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: Colors.grey.shade800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              mensagem,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.red, fontSize: 13),
            ),
            const SizedBox(height: 20),
            TextButton.icon(
              onPressed: () {
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute(builder: (_) => const ProfileScreen()),
                );
              },
              icon: const Icon(Icons.refresh),
              label: const Text('Tentar novamente'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _construirTelaSemLogin(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(22, 28, 22, 26),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE8E6ED)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset(
                'assets/logo.png',
                height: 108,
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) {
                  return Icon(
                    Icons.storefront_rounded,
                    size: 80,
                    color: diPertinRoxo.withValues(alpha: 0.85),
                  );
                },
              ),
              const SizedBox(height: 24),
              const Text(
                'Entre na sua conta',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF1A1A2E),
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Faça login para ver seu perfil, pedidos e benefícios.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.grey.shade600,
                  fontSize: 15,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Leva só um minuto.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.grey.shade500,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 26),
              FilledButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const LoginScreen(),
                    ),
                  );
                },
                style: FilledButton.styleFrom(
                  backgroundColor: diPertinLaranja,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 52),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: const Text(
                  'Entrar ou cadastrar',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _secaoTitulo(String titulo, {String? subtitulo}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          titulo,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w800,
            color: Colors.grey.shade700,
            letterSpacing: 0.2,
          ),
        ),
        if (subtitulo != null) ...[
          const SizedBox(height: 4),
          Text(
            subtitulo,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey.shade600,
              height: 1.35,
            ),
          ),
        ],
      ],
    );
  }

  Widget _construirTelaComLogin(
    BuildContext context,
    String email,
    Map<String, dynamic> userData, {
    required double saldoCarteira,
  }) {
    final String nome = userData['nome'] ?? 'Sem nome';
    final String role = userData['role'] ?? 'cliente';
    final bool cpfBloqueado = CpfPerfilUsuario.edicaoBloqueada(userData);
    final String cpfLegenda = CpfPerfilUsuario.textoListaPerfil(userData);
    final String enderecoPadrao = userData['endereco_padrao'] ?? '';
    final String nomeLojaDoc = userData['loja_nome'] ?? userData['nome_loja'] ?? '';
    final String fotoPerfil = userData['foto_perfil'] ?? '';

    final String ownerUid =
        (userData['lojista_owner_uid'] ?? '').toString().trim();
    final bool isColaborador = ownerUid.isNotEmpty;

    // Colaborador: busca dados da loja do dono em background.
    if (isColaborador && _ownerUidCache != ownerUid) {
      _ownerUidCache = ownerUid;
      FirebaseFirestore.instance
          .collection('users')
          .doc(ownerUid)
          .get()
          .then((ownerDoc) {
        if (ownerDoc.exists && mounted) {
          final d = ownerDoc.data() ?? {};
          final s = d['status_loja']?.toString() ?? 'pendente';
          final n = (d['loja_nome'] ?? d['nome_loja'] ?? d['nome'] ?? '')
              .toString();
          if (_statusLojaDono != s || _nomeLojaDono != n) {
            setState(() {
              _statusLojaDono = s;
              _nomeLojaDono = n;
            });
          }
        }
      });
    }

    final String statusLoja = isColaborador
        ? (_statusLojaDono ?? userData['status_loja'] ?? 'pendente')
        : (userData['status_loja'] ?? 'pendente');
    final String statusEntregador =
        userData['entregador_status'] ?? 'pendente';

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: GestureDetector(
              onTap: () => _mostrarOpcoesFotoPerfil(context, fotoPerfil),
              child: Stack(
                children: [
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Color(0x12000000),
                          blurRadius: 8,
                          offset: Offset(0, 2),
                        ),
                      ],
                    ),
                    child: CircleAvatar(
                      radius: 52,
                      backgroundColor: diPertinRoxo.withValues(alpha: 0.1),
                      backgroundImage: fotoPerfil.isNotEmpty
                          ? NetworkImage(fotoPerfil)
                          : null,
                      child: _isUploadingFoto
                          ? const SizedBox(
                              width: 32,
                              height: 32,
                              child: CircularProgressIndicator(
                                strokeWidth: 3,
                                color: diPertinRoxo,
                              ),
                            )
                          : fotoPerfil.isEmpty
                              ? const Icon(
                                  Icons.person,
                                  size: 56,
                                  color: diPertinRoxo,
                                )
                              : null,
                    ),
                  ),
                  Positioned(
                    bottom: 2,
                    right: 2,
                    child: Container(
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(
                        color: diPertinRoxo,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2.5),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x30000000),
                            blurRadius: 6,
                            offset: Offset(0, 2),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.camera_alt_rounded,
                        size: 16,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          Center(
            child: Text(
              nome,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: diPertinRoxo,
                letterSpacing: -0.3,
              ),
            ),
          ),
          const SizedBox(height: 8),
          () {
            final String nomeLoja = isColaborador
                ? (_nomeLojaDono ?? nomeLojaDoc)
                : nomeLojaDoc;
            if (nomeLoja.isNotEmpty) {
              return Center(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: diPertinLaranja.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: diPertinLaranja.withValues(alpha: 0.25),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.storefront_rounded,
                        size: 18,
                        color: diPertinLaranja.withValues(alpha: 0.85),
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          nomeLoja,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 14,
                            color: diPertinLaranja,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }
            return Center(
              child: Chip(
                label: Text(
                  _rotuloTipoPerfil(role),
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
                backgroundColor: diPertinRoxo.withValues(alpha: 0.1),
                side: BorderSide(color: diPertinRoxo.withValues(alpha: 0.25)),
                padding: const EdgeInsets.symmetric(horizontal: 4),
              ),
            );
          }(),
          const SizedBox(height: 6),
          Center(
            child: Text(
              email,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
            ),
          ),
          const SizedBox(height: 16),
          Center(
            child: FilledButton.tonalIcon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => EditProfileScreen(
                      nomeAtual: nome,
                      enderecoAtual: enderecoPadrao,
                      role: role,
                      nomeLojaAtual: nomeLojaDoc,
                    ),
                  ),
                );
              },
              icon: const Icon(Icons.edit_outlined, size: 20),
              label: const Text('Editar perfil'),
              style: FilledButton.styleFrom(
                foregroundColor: diPertinRoxo,
                backgroundColor: diPertinRoxo.withValues(alpha: 0.12),
              ),
            ),
          ),

          const SizedBox(height: 24),

          if (saldoCarteira > 0) ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.green.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.account_balance_wallet_outlined,
                      color: Colors.green.shade700, size: 28),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Saldo em conta',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.green.shade800,
                          ),
                        ),
                        Text(
                          'R\$ ${saldoCarteira.toStringAsFixed(2)}',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: Colors.green.shade800,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    'Valor disponível\nem sua carteira',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey.shade700,
                      height: 1.25,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
          ],

          _secaoTitulo(
            'Atividades',
            subtitulo: 'Pedidos e suporte',
          ),
          const SizedBox(height: 10),
          _buildMenuCard(
            children: [
              _buildMenuItem(
                icon: Icons.receipt_long_outlined,
                color: diPertinRoxo,
                title: 'Meus pedidos',
                subtitle: 'Acompanhe suas compras',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const OrdersScreen()),
                ),
              ),
              Divider(height: 1, color: Colors.grey.shade200),
              _buildMenuItem(
                icon: Icons.support_agent_outlined,
                color: diPertinLaranja,
                title: 'Central de ajuda',
                subtitle: 'Fale com nossa equipe',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const ChatSuporteScreen(),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 24),

          _secaoTitulo(
            'Dados da conta',
            subtitulo: 'Documentos e tipo de acesso',
          ),
          const SizedBox(height: 10),
          _buildMenuCard(
            children: [
              _buildMenuItem(
                icon: Icons.badge_outlined,
                color: Colors.grey.shade700,
                title: 'CPF',
                subtitle: cpfLegenda,
                trailing: Icon(
                  cpfBloqueado ? Icons.lock_outline : Icons.edit_outlined,
                  size: 18,
                  color: Colors.grey,
                ),
                onTap: cpfBloqueado
                    ? null
                    : () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => EditProfileScreen(
                              nomeAtual: nome,
                              enderecoAtual: enderecoPadrao,
                              role: role,
                              nomeLojaAtual: nomeLojaDoc,
                            ),
                          ),
                        );
                      },
              ),
              Divider(height: 1, color: Colors.grey.shade200),
              _buildMenuItem(
                icon: Icons.verified_user_outlined,
                color: Colors.grey.shade700,
                title: 'Tipo de perfil',
                subtitle: _rotuloTipoPerfil(role),
                trailing: const SizedBox(),
                onTap: null,
              ),
            ],
          ),

          const SizedBox(height: 24),

          _secaoTitulo(
            'Configurações',
            subtitulo: 'Ajustes do aplicativo',
          ),
          const SizedBox(height: 10),
          _buildMenuCard(
            children: [
              _buildMenuItem(
                icon: Icons.settings_outlined,
                color: diPertinRoxo,
                title: 'Configurações',
                subtitle:
                    'Preferências, políticas e solicitação de exclusão de conta',
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const ConfiguracoesScreen(),
                    ),
                  );
                },
              ),
            ],
          ),

          const SizedBox(height: 28),

          if (role == 'cliente') ...[
            _secaoTitulo(
              'Quero ser parceiro',
              subtitulo: 'Venda na plataforma ou faça entregas na sua região',
            ),
            const SizedBox(height: 10),
            _buildMenuCard(
              children: [
                _buildMenuItem(
                  icon: Icons.storefront_outlined,
                  color: diPertinLaranja,
                  title: 'Quero vender',
                  subtitle: 'Cadastro de lojista',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const LojistaFormScreen(),
                    ),
                  ),
                ),
                Divider(height: 1, color: Colors.grey.shade200),
                _buildMenuItem(
                  icon: Icons.delivery_dining_outlined,
                  color: diPertinLaranja,
                  title: 'Quero entregar',
                  subtitle: 'Cadastro de entregador',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const EntregadorFormScreen(),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
          ],

          if (role == 'lojista') ...[
            _secaoTitulo(
              'Painel da loja',
              subtitulo: 'Gerencie pedidos e estoque',
            ),
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: () =>
                  _abrirPainelLojistaOuCorrecao(context, userData),
              icon: Icon(
                ContaBloqueioLojistaService.estaBloqueadoParaOperacoes(userData)
                    ? Icons.block
                    : (ContaBloqueioLojistaService
                            .lojaRecusadaSomenteCorrecaoCadastro(userData)
                        ? Icons.error_outline
                        : (_statusLojaAprovada(statusLoja)
                            ? Icons.dashboard_outlined
                            : Icons.hourglass_empty_rounded)),
                color: Colors.white,
              ),
              label: Text(
                ContaBloqueioLojistaService.estaBloqueadoParaOperacoes(userData)
                    ? 'Acesso bloqueado'
                    : (ContaBloqueioLojistaService
                            .lojaRecusadaSomenteCorrecaoCadastro(userData)
                        ? 'Corrigir cadastro da loja'
                        : (_statusLojaAprovada(statusLoja)
                            ? 'Acessar painel da loja'
                            : 'Acompanhar análise da loja')),
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
              style: FilledButton.styleFrom(
                backgroundColor:
                    ContaBloqueioLojistaService.estaBloqueadoParaOperacoes(
                            userData)
                        ? Colors.red.shade700
                        : (ContaBloqueioLojistaService
                                .lojaRecusadaSomenteCorrecaoCadastro(userData)
                            ? Colors.red.shade700
                            : (_statusLojaAprovada(statusLoja)
                                ? diPertinLaranja
                                : Colors.orange.shade600)),
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 52),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
            const SizedBox(height: 24),
          ],

          if (role == 'entregador') ...[
            _secaoTitulo(
              'Painel de entregas',
              subtitulo: 'Corridas e ganhos',
            ),
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: () =>
                  _abrirPainelEntregadorOuCorrecao(context, userData),
              icon: Icon(
                ContaBloqueioEntregadorService.estaBloqueadoParaOperacoes(
                        userData)
                    ? (ContaBloqueioEntregadorService.isBloqueioTemporarioTipo(
                            userData)
                        ? Icons.schedule_rounded
                        : Icons.block)
                    : (statusEntregador == 'aprovado'
                        ? Icons.motorcycle_outlined
                        : (statusEntregador == 'bloqueado'
                            ? Icons.error_outline
                            : Icons.hourglass_empty_rounded)),
                color: Colors.white,
              ),
              label: Text(
                ContaBloqueioEntregadorService.estaBloqueadoParaOperacoes(
                        userData)
                    ? (ContaBloqueioEntregadorService.isBloqueioTemporarioTipo(
                            userData)
                        ? 'Bloqueio temporário — ver detalhes'
                        : 'Acesso bloqueado — ver detalhes')
                    : (statusEntregador == 'aprovado'
                        ? 'Acessar painel de entregas'
                        : (statusEntregador == 'bloqueado'
                            ? 'Corrigir cadastro de entregador'
                            : 'Cadastro em análise')),
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
              style: FilledButton.styleFrom(
                backgroundColor:
                    ContaBloqueioEntregadorService.estaBloqueadoParaOperacoes(
                            userData)
                        ? Colors.red.shade700
                        : (statusEntregador == 'aprovado'
                            ? const Color(0xFF263238)
                            : (statusEntregador == 'bloqueado'
                                ? Colors.red.shade700
                                : Colors.orange.shade600)),
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 52),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
            const SizedBox(height: 24),
          ],

          const SizedBox(height: 28),

          Center(
            child: TextButton.icon(
              onPressed: () => _confirmarSair(context),
              icon: const Icon(Icons.logout_rounded, color: Colors.red),
              label: const Text(
                'Sair da conta',
                style: TextStyle(
                  color: Colors.red,
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _mostrarOpcoesFotoPerfil(BuildContext context, String fotoAtual) {
    final temFoto = fotoAtual.isNotEmpty;

    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Text(
                  'Foto do perfil',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: Colors.grey.shade800,
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _opcaoFotoCircular(
                      icone: Icons.camera_alt_rounded,
                      cor: diPertinRoxo,
                      rotulo: 'Câmera',
                      onTap: () async {
                        Navigator.pop(ctx);
                        await Future<void>.delayed(
                          const Duration(milliseconds: 250),
                        );
                        if (!mounted) return;
                        await _escolherFoto(context, ImageSource.camera);
                      },
                    ),
                    _opcaoFotoCircular(
                      icone: Icons.photo_library_rounded,
                      cor: diPertinLaranja,
                      rotulo: 'Galeria',
                      onTap: () async {
                        Navigator.pop(ctx);
                        await Future<void>.delayed(
                          const Duration(milliseconds: 250),
                        );
                        if (!mounted) return;
                        await _escolherFoto(context, ImageSource.gallery);
                      },
                    ),
                    if (temFoto)
                      _opcaoFotoCircular(
                        icone: Icons.zoom_in_rounded,
                        cor: Colors.blueGrey,
                        rotulo: 'Ver foto',
                        onTap: () {
                          Navigator.pop(ctx);
                          _mostrarFotoPerfilAmpliada(context, fotoAtual);
                        },
                      ),
                    if (temFoto)
                      _opcaoFotoCircular(
                        icone: Icons.delete_outline_rounded,
                        cor: Colors.red.shade600,
                        rotulo: 'Remover',
                        onTap: () async {
                          Navigator.pop(ctx);
                          await Future<void>.delayed(
                            const Duration(milliseconds: 250),
                          );
                          if (!mounted) return;
                          await _confirmarRemoverFoto(context);
                        },
                      ),
                  ],
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _opcaoFotoCircular({
    required IconData icone,
    required Color cor,
    required String rotulo,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: cor.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icone, color: cor, size: 26),
          ),
          const SizedBox(height: 8),
          Text(
            rotulo,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade700,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _escolherFoto(BuildContext context, ImageSource source) async {
    if (source == ImageSource.camera) {
      final r = await PermissoesAppService.garantirCamera();
      if (r != ResultadoPermissao.concedida) {
        if (context.mounted) PermissoesFeedback.camera(context, r);
        return;
      }
    } else {
      final r = await PermissoesAppService.garantirGaleriaFotos();
      if (r != ResultadoPermissao.concedida) {
        if (context.mounted) PermissoesFeedback.galeria(context, r);
        return;
      }
    }

    final picker = ImagePicker();
    final XFile? imagem = await picker.pickImage(
      source: source,
      maxWidth: 800,
      maxHeight: 800,
      imageQuality: 80,
    );
    if (imagem == null) return;

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    setState(() => _isUploadingFoto = true);

    try {
      final file = File(imagem.path);
      final ref = FirebaseStorage.instance
          .ref()
          .child('fotos_perfil')
          .child('$uid.jpg');

      await ref.putFile(
        file,
        SettableMetadata(contentType: 'image/jpeg'),
      );
      final url = await ref.getDownloadURL();

      await FirebaseFirestore.instance.collection('users').doc(uid).update({
        'foto_perfil': url,
      });

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Foto atualizada com sucesso!'),
            backgroundColor: Colors.green.shade700,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Erro ao enviar a foto. Tente novamente.'),
            backgroundColor: Colors.red.shade700,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isUploadingFoto = false);
    }
  }

  Future<void> _confirmarRemoverFoto(BuildContext context) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.delete_outline_rounded, color: Colors.red),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Remover foto?',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
        content: const Text(
          'Sua foto de perfil será removida.',
          style: TextStyle(height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red.shade700,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remover'),
          ),
        ],
      ),
    );

    if (confirmar != true) return;

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    setState(() => _isUploadingFoto = true);

    try {
      try {
        await FirebaseStorage.instance
            .ref()
            .child('fotos_perfil')
            .child('$uid.jpg')
            .delete();
      } on FirebaseException catch (_) {
        // Arquivo pode não existir no Storage; continua limpando o Firestore.
      }

      await FirebaseFirestore.instance.collection('users').doc(uid).update({
        'foto_perfil': FieldValue.delete(),
      });

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Foto removida.'),
            backgroundColor: Colors.grey.shade700,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Erro ao remover a foto.'),
            backgroundColor: Colors.red.shade700,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isUploadingFoto = false);
    }
  }

  void _mostrarFotoPerfilAmpliada(BuildContext context, String url) {
    showDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withValues(alpha: 0.45),
      builder: (dialogContext) {
        final double w = MediaQuery.sizeOf(dialogContext).width;
        final double side = (w - 56).clamp(220.0, 288.0);

        return Dialog(
          backgroundColor: Colors.transparent,
          elevation: 0,
          insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: Material(
            color: Colors.white,
            elevation: 12,
            shadowColor: Colors.black26,
            borderRadius: BorderRadius.circular(16),
            clipBehavior: Clip.antiAlias,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: side),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 10, 4, 8),
                    child: Row(
                      children: [
                        Icon(
                          Icons.photo_outlined,
                          size: 20,
                          color: diPertinRoxo.withValues(alpha: 0.9),
                        ),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text(
                            'Foto do perfil',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              letterSpacing: -0.2,
                              color: Color(0xFF1A1A1A),
                            ),
                          ),
                        ),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          icon: Icon(
                            Icons.close_rounded,
                            color: Colors.grey.shade600,
                            size: 22,
                          ),
                          onPressed: () => Navigator.of(dialogContext).pop(),
                        ),
                      ],
                    ),
                  ),
                  Divider(height: 1, thickness: 1, color: Colors.grey.shade200),
                  ColoredBox(
                    color: Colors.grey.shade50,
                    child: SizedBox(
                      width: side,
                      height: side,
                      child: InteractiveViewer(
                        minScale: 1,
                        maxScale: 3.2,
                        boundaryMargin: const EdgeInsets.all(20),
                        child: Image.network(
                          url,
                          fit: BoxFit.contain,
                          loadingBuilder: (context, child, loadingProgress) {
                            if (loadingProgress == null) return child;
                            return Center(
                              child: SizedBox(
                                width: 28,
                                height: 28,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                  color: diPertinRoxo.withValues(alpha: 0.85),
                                ),
                              ),
                            );
                          },
                          errorBuilder: (context, error, stackTrace) {
                            return Icon(
                              Icons.broken_image_outlined,
                              color: Colors.grey.shade400,
                              size: 48,
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
                    child: Text(
                      'Use dois dedos para ampliar',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                        height: 1.2,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildMenuCard({required List<Widget> children}) {
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

  Widget _buildMenuItem({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    VoidCallback? onTap,
    Widget? trailing,
  }) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: color, size: 22),
      ),
      title: Text(
        title,
        style: const TextStyle(
          fontWeight: FontWeight.w700,
          fontSize: 15,
          color: Color(0xFF1A1A2E),
        ),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
      ),
      trailing: trailing ??
          (onTap != null
              ? Icon(Icons.chevron_right_rounded, color: Colors.grey.shade400)
              : null),
      onTap: onTap,
    );
  }
}
