import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/cliente_assinatura_model.dart';
import '../services/assinatura_gestao_comercial_refresh.dart';
import '../services/assinatura_gestao_comercial_service.dart';

/// Gate do Módulo Fiscal: exige módulo `emissao_nfe` na assinatura ativa.
///
/// Deve ser usado **dentro** de [GestaoComercialAccessGate] (já com plano GC).
/// Sem o módulo → [semModulo] (tela premium de upgrade).
class ModuloFiscalAccessGate extends StatefulWidget {
  const ModuloFiscalAccessGate({
    super.key,
    required this.child,
    required this.semModulo,
  });

  final Widget child;
  final Widget semModulo;

  @override
  State<ModuloFiscalAccessGate> createState() => _ModuloFiscalAccessGateState();
}

class _ModuloFiscalAccessGateState extends State<ModuloFiscalAccessGate> {
  bool _carregandoCtx = true;
  bool _erro = false;
  AssinaturaGestaoComercialContexto? _ctx;
  int _childKey = 0;
  bool _tinhaAcesso = false;

  @override
  void initState() {
    super.initState();
    AssinaturaGestaoComercialRefresh.instance.addListener(_onRefresh);
    _carregarContexto();
  }

  @override
  void dispose() {
    AssinaturaGestaoComercialRefresh.instance.removeListener(_onRefresh);
    super.dispose();
  }

  void _onRefresh() {
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

  List<ClienteAssinaturaModel> _parse(
    QuerySnapshot<Map<String, dynamic>>? snap,
  ) {
    if (snap == null) return const [];
    return snap.docs.map(ClienteAssinaturaModel.fromFirestore).toList();
  }

  Widget _conteudo(List<ClienteAssinaturaModel> assinaturas) {
    final ctx = _ctx;
    if (ctx == null) return _loading();

    final tem = AssinaturaGestaoComercialService.lojistaTemModuloEmissaoNfe(
      assinaturas,
      ctx,
    );

    if (tem && !_tinhaAcesso) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() {
          _tinhaAcesso = true;
          _childKey++;
        });
      });
    } else if (!tem && _tinhaAcesso) {
      _tinhaAcesso = false;
    }

    if (!tem) return widget.semModulo;

    return KeyedSubtree(
      key: ValueKey('fiscal-child-$_childKey'),
      child: widget.child,
    );
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || _erro) return _erroUi();
    if (_carregandoCtx || _ctx == null) return _loading();

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('assinaturas_clientes')
          .where('store_id', isEqualTo: uid)
          .snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
          return _loading();
        }
        if (snap.hasError) return _erroUi();
        return _conteudo(_parse(snap.data));
      },
    );
  }

  Widget _loading() {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F4F8),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 36,
              height: 36,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: Color(0xFF6A1B9A),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Verificando acesso ao Módulo Fiscal…',
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

  Widget _erroUi() {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F4F8),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline_rounded,
                  size: 40, color: Color(0xFFEF4444)),
              const SizedBox(height: 12),
              Text(
                'Não foi possível verificar o acesso fiscal.',
                textAlign: TextAlign.center,
                style: GoogleFonts.plusJakartaSans(
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF1A1A2E),
                ),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => _carregarContexto(),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF6A1B9A),
                ),
                child: const Text('Tentar novamente'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
