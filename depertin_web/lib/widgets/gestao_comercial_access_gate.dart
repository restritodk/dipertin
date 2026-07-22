import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/cliente_assinatura_model.dart';
import '../services/assinatura_gestao_comercial_refresh.dart';
import '../services/assinatura_gestao_comercial_service.dart';
import 'gestao_bloqueada_screen.dart';
import 'gestao_comercial_bloqueio_admin_screen.dart';

/// Intercepta todas as rotas do Gestão Comercial e exibe:
/// - bloqueio admin (status suspenso)
/// - bloqueio por inadimplência
/// - upsell sem plano
/// - conteúdo liberado (`child`)
class GestaoComercialAccessGate extends StatefulWidget {
  const GestaoComercialAccessGate({
    super.key,
    required this.child,
    required this.semPlano,
  });

  final Widget child;
  final Widget semPlano;

  @override
  State<GestaoComercialAccessGate> createState() =>
      _GestaoComercialAccessGateState();
}

class _GestaoComercialAccessGateState extends State<GestaoComercialAccessGate> {
  bool _carregandoCtx = true;
  bool _erro = false;
  AssinaturaGestaoComercialContexto? _ctx;
  int _childKey = 0;
  bool _tinhaAcesso = false;

  @override
  void initState() {
    super.initState();
    AssinaturaGestaoComercialRefresh.instance.addListener(_onRefreshSolicitado);
    _carregarContexto();
  }

  @override
  void dispose() {
    AssinaturaGestaoComercialRefresh.instance
        .removeListener(_onRefreshSolicitado);
    super.dispose();
  }

  void _onRefreshSolicitado() {
    if (!mounted) return;
    _carregarContexto(forceChildRemount: true);
  }

  Future<void> _carregarContexto({bool forceChildRemount = false}) async {
    if (mounted) {
      setState(() {
        _carregandoCtx = true;
        _erro = false;
      });
    }

    try {
      final ctx = await AssinaturaGestaoComercialService.carregarContexto()
          .timeout(const Duration(seconds: 15));
      if (!mounted) return;
      setState(() {
        _ctx = ctx;
        _carregandoCtx = false;
        if (forceChildRemount) _childKey++;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _carregandoCtx = false;
        _erro = true;
      });
    }
  }

  List<ClienteAssinaturaModel> _parseAssinaturas(
    QuerySnapshot<Map<String, dynamic>>? snap,
  ) {
    if (snap == null) return const [];
    return snap.docs.map(ClienteAssinaturaModel.fromFirestore).toList();
  }

  Widget _buildConteudo(
    List<ClienteAssinaturaModel> assinaturas,
    String uid,
  ) {
    final ctx = _ctx;
    if (ctx == null) return _buildCarregando();

    final bloqueioAdmin =
        AssinaturaGestaoComercialService.assinaturaBloqueioAdmin(
      assinaturas,
      ctx,
    );
    if (bloqueioAdmin != null) {
      return GestaoComercialBloqueioAdminScreen(
        assinatura: bloqueioAdmin,
        lojaId: uid,
        lojaNome: bloqueioAdmin.storeName,
        ownerName: bloqueioAdmin.ownerName,
        ownerEmail: bloqueioAdmin.email,
      );
    }

    final bloqueioPagamento =
        AssinaturaGestaoComercialService.assinaturaBloqueioInadimplencia(
      assinaturas,
      ctx,
    );
    if (bloqueioPagamento != null) {
      return GestaoBloqueadaScreen(
        assinatura: bloqueioPagamento,
        lojaId: uid,
        lojaNome: bloqueioPagamento.storeName,
        ownerName: bloqueioPagamento.ownerName,
        ownerEmail: bloqueioPagamento.email,
      );
    }

    final temAcesso =
        AssinaturaGestaoComercialService.lojistaTemAcessoGestaoComercial(
      assinaturas,
      ctx,
    );

    if (temAcesso && !_tinhaAcesso) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() {
          _tinhaAcesso = true;
          _childKey++;
        });
      });
    } else if (!temAcesso && _tinhaAcesso) {
      _tinhaAcesso = false;
    }

    if (!temAcesso) {
      return widget.semPlano;
    }

    return KeyedSubtree(
      key: ValueKey('gc-child-$_childKey'),
      child: widget.child,
    );
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;

    if (uid == null || _erro) {
      return _buildEstadoErro();
    }

    if (_carregandoCtx || _ctx == null) {
      return _buildCarregando();
    }

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('assinaturas_clientes')
          .where('store_id', isEqualTo: uid)
          .snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
          return _buildCarregando();
        }
        if (snap.hasError) {
          return _buildEstadoErro();
        }
        return _buildConteudo(_parseAssinaturas(snap.data), uid);
      },
    );
  }

  Widget _buildCarregando() {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F4F8),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 36,
              height: 36,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
            const SizedBox(height: 16),
            Text(
              'Verificando seu acesso ao Gestão Comercial…',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 14,
                color: const Color(0xFF64748B),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEstadoErro() {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F4F8),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: const Color(0xFF6A1B9A).withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.error_outline_rounded,
                color: Color(0xFF6A1B9A),
                size: 32,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Não foi possível verificar seu acesso.',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF1A1A2E),
              ),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => _carregarContexto(forceChildRemount: true),
              child: Text(
                'Tentar novamente',
                style: GoogleFonts.plusJakartaSans(
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF6A1B9A),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
