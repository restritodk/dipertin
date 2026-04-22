// Arquivo: lib/screens/entregador/configuracoes/acessibilidade_screen.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../../services/acessibilidade_prefs_service.dart';

const Color _roxo = Color(0xFF6A1B9A);
const Color _laranja = Color(0xFFFF8F00);

class AcessibilidadeScreen extends StatefulWidget {
  const AcessibilidadeScreen({super.key});

  @override
  State<AcessibilidadeScreen> createState() => _AcessibilidadeScreenState();
}

class _AcessibilidadeScreenState extends State<AcessibilidadeScreen> {
  final _svc = AcessibilidadePrefsService.instance;

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final docRef = uid == null
        ? null
        : FirebaseFirestore.instance.collection('users').doc(uid);

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F7),
      appBar: AppBar(
        title: const Text(
          'Acessibilidade',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        backgroundColor: _roxo,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: docRef == null
          ? const Center(child: Text('Você precisa estar autenticado.'))
          : StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: docRef.snapshots(),
              builder: (context, snap) {
                final data = snap.data?.data() ?? {};
                final ac = data['acessibilidade'] is Map
                    ? data['acessibilidade'] as Map
                    : {};
                final cfg = data['config'] is Map ? data['config'] as Map : {};
                final audicao =
                    StatusAuditivoX.fromCodigo(ac['audicao']?.toString());
                final vibracao = cfg['vibracao'] == true;
                final flash = cfg['flash'] == true;

                return ListView(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  children: [
                    _cartao(
                      icone: Icons.hearing_rounded,
                      titulo: 'Audição',
                      subtitulo:
                          'Informe sua condição auditiva. Usamos essa informação para priorizar chat e avisar lojistas e clientes.',
                      trailing: _ChipStatusAuditivo(status: audicao),
                      onTap: () async {
                        await Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => StatusAuditivoScreen(
                              inicial: audicao,
                            ),
                          ),
                        );
                      },
                    ),
                    _cartaoSwitch(
                      icone: Icons.vibration_rounded,
                      titulo: 'Vibração para solicitações',
                      subtitulo:
                          'Vibra ao receber nova corrida, além da notificação sonora.',
                      valor: vibracao,
                      onChanged: (v) async {
                        try {
                          await _svc.definirVibracao(v);
                        } catch (e) {
                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Não foi possível salvar: $e')),
                          );
                        }
                      },
                    ),
                    _cartaoSwitch(
                      icone: Icons.flash_on_rounded,
                      titulo: 'Flash na tela para solicitações',
                      subtitulo: 'Pisca a tela ao receber nova corrida.',
                      valor: flash,
                      onChanged: (v) async {
                        try {
                          await _svc.definirFlash(v);
                        } catch (e) {
                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Não foi possível salvar: $e')),
                          );
                        }
                      },
                    ),
                    const SizedBox(height: 24),
                  ],
                );
              },
            ),
    );
  }

  Widget _cartao({
    required IconData icone,
    required String titulo,
    required String subtitulo,
    required Widget trailing,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          leading: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: _roxo.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icone, color: _roxo, size: 22),
          ),
          title: Text(
            titulo,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
          ),
          subtitle: Text(
            subtitulo,
            style: const TextStyle(fontSize: 12, color: Colors.black54),
          ),
          trailing: trailing,
          onTap: onTap,
          isThreeLine: true,
        ),
      ),
    );
  }

  Widget _cartaoSwitch({
    required IconData icone,
    required String titulo,
    required String subtitulo,
    required bool valor,
    required ValueChanged<bool> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: SwitchListTile.adaptive(
          value: valor,
          onChanged: onChanged,
          activeThumbColor: _laranja,
          secondary: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: _roxo.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icone, color: _roxo, size: 22),
          ),
          title: Text(
            titulo,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
          ),
          subtitle: Text(
            subtitulo,
            style: const TextStyle(fontSize: 12, color: Colors.black54),
          ),
          isThreeLine: true,
        ),
      ),
    );
  }
}

class _ChipStatusAuditivo extends StatelessWidget {
  final StatusAuditivo status;
  const _ChipStatusAuditivo({required this.status});

  @override
  Widget build(BuildContext context) {
    final tem = status.temLimitacao;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: tem
            ? _laranja.withValues(alpha: 0.15)
            : Colors.grey.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        _textoCurto(status),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: tem ? _laranja : Colors.black54,
        ),
      ),
    );
  }

  String _textoCurto(StatusAuditivo s) {
    switch (s) {
      case StatusAuditivo.surdo:
        return 'Surdo';
      case StatusAuditivo.deficiencia:
        return 'Def. auditiva';
      case StatusAuditivo.normal:
        return 'Sem limitação';
    }
  }
}

/// Tela para o entregador selecionar o status auditivo.
class StatusAuditivoScreen extends StatefulWidget {
  final StatusAuditivo inicial;
  const StatusAuditivoScreen({super.key, required this.inicial});

  @override
  State<StatusAuditivoScreen> createState() => _StatusAuditivoScreenState();
}

class _StatusAuditivoScreenState extends State<StatusAuditivoScreen> {
  late StatusAuditivo _selecionado;
  bool _salvando = false;

  @override
  void initState() {
    super.initState();
    _selecionado = widget.inicial;
  }

  Future<void> _salvar() async {
    setState(() => _salvando = true);
    try {
      await AcessibilidadePrefsService.instance.definirAudicao(_selecionado);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Preferência atualizada.')),
      );
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao salvar: $e')),
      );
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F7),
      appBar: AppBar(
        title: const Text(
          'Status auditivo',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        backgroundColor: _roxo,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Column(
        children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Escolha a opção que melhor representa sua audição. Essa informação ajuda lojistas e clientes a se comunicarem com você pelo chat.',
              style: TextStyle(color: Colors.black54, fontSize: 13),
            ),
          ),
          ...StatusAuditivo.values.map(
            (s) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Material(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                clipBehavior: Clip.antiAlias,
                child: RadioListTile<StatusAuditivo>(
                  value: s,
                  groupValue: _selecionado,
                  title: Text(
                    s.rotulo,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  activeColor: _laranja,
                  onChanged: (v) {
                    if (v == null) return;
                    setState(() => _selecionado = v);
                  },
                ),
              ),
            ),
          ),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: _laranja,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                onPressed: _salvando ? null : _salvar,
                child: _salvando
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2.5,
                        ),
                      )
                    : const Text(
                        'Salvar',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
