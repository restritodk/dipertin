import 'dart:math' show min, Random;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:depertin_web/theme/painel_admin_theme.dart';
import 'package:depertin_web/widgets/botao_suporte_flutuante.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

class CuponsScreen extends StatefulWidget {
  const CuponsScreen({super.key});

  @override
  State<CuponsScreen> createState() => _CuponsScreenState();
}

class _CuponsScreenState extends State<CuponsScreen> {
  static const _roxo = PainelAdminTheme.roxo;
  static const _laranja = PainelAdminTheme.laranja;

  String _gerarCodigo() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final r = Random();
    return List.generate(8, (_) => chars[r.nextInt(chars.length)]).join();
  }

  InputDecoration _dec(String label) => InputDecoration(
        labelText: label,
        filled: true,
        fillColor: const Color(0xFFF8F7FC),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.grey.shade300)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.grey.shade300)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: _roxo, width: 1.5)),
      );

  Widget _fieldTF({
    required TextEditingController controller,
    required String label,
    TextInputType keyboardType = TextInputType.text,
    List<TextInputFormatter>? inputFormatters,
  }) =>
      TextField(
        controller: controller,
        keyboardType: keyboardType,
        inputFormatters: inputFormatters,
        decoration: _dec(label),
      );

  Widget _dialogHeader(String titulo, IconData icon) => Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(22, 20, 22, 18),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              _roxo.withValues(alpha: 0.09),
              _roxo.withValues(alpha: 0.03)
            ],
          ),
          border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                      color: _roxo.withValues(alpha: 0.12),
                      blurRadius: 12,
                      offset: const Offset(0, 4))
                ],
              ),
              child: Icon(icon, color: _roxo, size: 22),
            ),
            const SizedBox(width: 14),
            Text(titulo,
                style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: _roxo)),
          ],
        ),
      );

  void _abrirFormulario({String? docId, Map<String, dynamic>? dados}) {
    final isEdit = docId != null;
    final codigoC = TextEditingController(
        text: isEdit ? (dados!['codigo'] ?? '') : _gerarCodigo());
    final valorC = TextEditingController(
        text: isEdit ? (dados!['valor']?.toString() ?? '') : '');
    final limiteC = TextEditingController(
        text: isEdit ? (dados!['limite_usos']?.toString() ?? '') : '');
    String tipo = isEdit ? (dados!['tipo'] ?? 'porcentagem') : 'porcentagem';
    DateTime? validade = isEdit && dados!['validade'] != null
        ? (dados['validade'] as Timestamp).toDate()
        : null;
    bool ativo = isEdit ? (dados!['ativo'] ?? true) : true;
    var loading = false;

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.45),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) {
          final mq = MediaQuery.sizeOf(ctx);
          final w = min(480.0, mq.width - 40);

          Future<void> salvar() async {
            if (codigoC.text.trim().isEmpty || valorC.text.trim().isEmpty) {
              ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(content: Text('Preencha código e valor.')));
              return;
            }
            setS(() => loading = true);
            try {
              final d = <String, dynamic>{
                'codigo': codigoC.text.trim().toUpperCase(),
                'tipo': tipo,
                'valor':
                    double.tryParse(valorC.text.replaceAll(',', '.')) ?? 0.0,
                'limite_usos': int.tryParse(limiteC.text) ?? 0,
                'usos_atual': isEdit ? (dados!['usos_atual'] ?? 0) : 0,
                'ativo': ativo,
                if (validade != null) 'validade': Timestamp.fromDate(validade!),
                if (!isEdit) 'data_criacao': FieldValue.serverTimestamp(),
                if (isEdit) 'data_atualizacao': FieldValue.serverTimestamp(),
              };
              final col = FirebaseFirestore.instance.collection('cupons');
              if (isEdit) {
                await col.doc(docId).update(d);
              } else {
                await col.add(d);
              }
              if (ctx.mounted) Navigator.pop(ctx);
            } catch (e) {
              if (ctx.mounted) {
                ScaffoldMessenger.of(ctx)
                    .showSnackBar(SnackBar(content: Text('Erro: $e')));
              }
            } finally {
              if (ctx.mounted) setS(() => loading = false);
            }
          }

          return Dialog(
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20)),
            clipBehavior: Clip.antiAlias,
            backgroundColor: Colors.white,
            child: SizedBox(
              width: w,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _dialogHeader(
                    isEdit ? 'Editar cupom' : 'Novo cupom',
                    isEdit
                        ? Icons.edit_note_rounded
                        : Icons.local_offer,
                  ),
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(22, 20, 22, 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: _fieldTF(
                                  controller: codigoC,
                                  label: 'Código do cupom',
                                  inputFormatters: [
                                    FilteringTextInputFormatter.allow(
                                        RegExp(r'[A-Za-z0-9]'))
                                  ],
                                ),
                              ),
                              const SizedBox(width: 10),
                              IconButton.filledTonal(
                                tooltip: 'Gerar código aleatório',
                                icon: const Icon(Icons.refresh_rounded),
                                onPressed: () =>
                                    setS(() => codigoC.text = _gerarCodigo()),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          DropdownButtonFormField<String>(
                            value: tipo,
                            decoration: _dec('Tipo de desconto'),
                            items: const [
                              DropdownMenuItem(
                                  value: 'porcentagem',
                                  child: Text('Percentual (%)')),
                              DropdownMenuItem(
                                  value: 'fixo',
                                  child: Text('Valor fixo (R\$)')),
                            ],
                            onChanged: (v) => setS(() => tipo = v!),
                          ),
                          const SizedBox(height: 16),
                          _fieldTF(
                            controller: valorC,
                            label: tipo == 'porcentagem'
                                ? 'Desconto (%)'
                                : 'Desconto (R\$)',
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                          ),
                          const SizedBox(height: 16),
                          _fieldTF(
                            controller: limiteC,
                            label: 'Limite de usos (0 = ilimitado)',
                            keyboardType: TextInputType.number,
                          ),
                          const SizedBox(height: 16),
                          InkWell(
                            onTap: () async {
                              final d = await showDatePicker(
                                context: ctx,
                                initialDate: validade ??
                                    DateTime.now()
                                        .add(const Duration(days: 30)),
                                firstDate: DateTime.now(),
                                lastDate: DateTime.now()
                                    .add(const Duration(days: 365 * 3)),
                              );
                              if (d != null) setS(() => validade = d);
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 14),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF8F7FC),
                                borderRadius: BorderRadius.circular(12),
                                border:
                                    Border.all(color: Colors.grey.shade300),
                              ),
                              child: Row(
                                children: [
                                  Icon(Icons.calendar_today_outlined,
                                      size: 18, color: Colors.grey.shade600),
                                  const SizedBox(width: 8),
                                  Text(
                                    validade != null
                                        ? 'Válido até: ${DateFormat('dd/MM/yyyy').format(validade!)}'
                                        : 'Sem validade definida',
                                    style: TextStyle(
                                        color: Colors.grey.shade700,
                                        fontSize: 14),
                                  ),
                                  const Spacer(),
                                  if (validade != null)
                                    GestureDetector(
                                      onTap: () =>
                                          setS(() => validade = null),
                                      child: Icon(Icons.close_rounded,
                                          size: 18,
                                          color: Colors.grey.shade500),
                                    ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          SwitchListTile(
                            value: ativo,
                            onChanged: (v) => setS(() => ativo = v),
                            title: const Text('Cupom ativo'),
                            subtitle: Text(ativo
                                ? 'Disponível para uso no app'
                                : 'Desativado temporariamente'),
                            activeColor: _laranja,
                            contentPadding: EdgeInsets.zero,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const Divider(height: 1),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed:
                              loading ? null : () => Navigator.pop(ctx),
                          child: const Text('Cancelar',
                              style: TextStyle(color: _roxo)),
                        ),
                        const SizedBox(width: 8),
                        FilledButton.icon(
                          onPressed: loading ? null : salvar,
                          icon: loading
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: Colors.white))
                              : const Icon(Icons.check_rounded, size: 20),
                          label: Text(loading
                              ? 'Salvando…'
                              : isEdit
                                  ? 'Salvar alterações'
                                  : 'Criar cupom'),
                          style: FilledButton.styleFrom(
                            backgroundColor: _laranja,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 22, vertical: 14),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _confirmarExclusao(String docId, String codigo) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Row(children: [
          Icon(Icons.warning_amber_rounded, color: _laranja),
          const SizedBox(width: 12),
          const Expanded(
              child: Text('Remover cupom',
                  style: TextStyle(fontWeight: FontWeight.w700))),
        ]),
        content: Text(
            'O cupom "$codigo" será removido permanentemente. Deseja continuar?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancelar')),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFB91C1C),
                foregroundColor: Colors.white),
            child: const Text('Remover'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await FirebaseFirestore.instance.collection('cupons').doc(docId).delete();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PainelAdminTheme.fundoCanvas,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Material(
            color: Colors.white,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(28, 28, 28, 20),
              child: Row(
                children: [
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Cupons e Promoções',
                          style: TextStyle(
                              fontSize: 26,
                              fontWeight: FontWeight.w800,
                              color: _roxo,
                              letterSpacing: -0.5),
                        ),
                        SizedBox(height: 6),
                        Text(
                          'Crie códigos de desconto percentual ou valor fixo para o app.',
                          style: TextStyle(
                              color: PainelAdminTheme.textoSecundario,
                              fontSize: 15),
                        ),
                      ],
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: _abrirFormulario,
                    icon: const Icon(Icons.add_rounded, size: 20),
                    label: const Text('Novo cupom'),
                    style: FilledButton.styleFrom(
                      backgroundColor: _laranja,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 14),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Divider(height: 1, color: Colors.grey.shade200),
          Expanded(child: _buildLista()),
        ],
      ),
      floatingActionButton: const BotaoSuporteFlutuante(),
    );
  }

  Widget _buildLista() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('cupons')
          .orderBy('data_criacao', descending: true)
          .snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snap.data?.docs ?? [];
        if (docs.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.local_offer_outlined,
                    size: 56, color: _roxo.withValues(alpha: 0.3)),
                const SizedBox(height: 16),
                Text('Nenhum cupom cadastrado.',
                    style: TextStyle(
                        fontSize: 16, color: Colors.grey.shade600)),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _abrirFormulario,
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Criar primeiro cupom'),
                  style: FilledButton.styleFrom(
                      backgroundColor: _laranja,
                      foregroundColor: Colors.white),
                ),
              ],
            ),
          );
        }

        return Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 860),
            child: ListView.separated(
              padding: const EdgeInsets.all(24),
              itemCount: docs.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (_, i) {
                final doc = docs[i];
                final d = doc.data() as Map<String, dynamic>;
                final codigo = d['codigo']?.toString() ?? '—';
                final tipo = d['tipo'] ?? 'porcentagem';
                final valor = (d['valor'] as num?)?.toDouble() ?? 0;
                final limite = d['limite_usos'] ?? 0;
                final usos = d['usos_atual'] ?? 0;
                final ativo = d['ativo'] ?? true;
                final validade = d['validade'] as Timestamp?;

                final descontoLabel = tipo == 'porcentagem'
                    ? '${valor.toStringAsFixed(0)}% OFF'
                    : 'R\$ ${valor.toStringAsFixed(2)} OFF';

                final expirado = validade != null &&
                    validade.toDate().isBefore(DateTime.now());

                return Material(
                  color: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                    side: BorderSide(
                        color: expirado
                            ? const Color(0xFFB91C1C).withValues(alpha: 0.3)
                            : !ativo
                                ? Colors.grey.shade300
                                : Colors.grey.shade200),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 18, vertical: 14),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: ativo && !expirado
                                ? _roxo.withValues(alpha: 0.08)
                                : Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            codigo,
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 16,
                              color: ativo && !expirado
                                  ? _roxo
                                  : Colors.grey.shade500,
                              letterSpacing: 1.5,
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 4),
                                    decoration: BoxDecoration(
                                      color:
                                          _laranja.withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Text(
                                      descontoLabel,
                                      style: const TextStyle(
                                        color: _laranja,
                                        fontWeight: FontWeight.w800,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  if (expirado)
                                    _badge('EXPIRADO',
                                        const Color(0xFFB91C1C))
                                  else if (!ativo)
                                    _badge('INATIVO', Colors.grey.shade600),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Wrap(
                                spacing: 12,
                                children: [
                                  _infoSmall(
                                      Icons.bar_chart_rounded,
                                      '$usos / ${limite == 0 ? '∞' : '$limite'} usos'),
                                  if (validade != null)
                                    _infoSmall(
                                      Icons.calendar_today_outlined,
                                      'Válido até ${DateFormat('dd/MM/yy').format(validade.toDate())}',
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        Switch(
                          value: ativo,
                          activeColor: _laranja,
                          onChanged: (v) => FirebaseFirestore.instance
                              .collection('cupons')
                              .doc(doc.id)
                              .update({'ativo': v}),
                        ),
                        IconButton(
                          tooltip: 'Editar',
                          icon: Icon(Icons.edit_outlined, color: _roxo),
                          onPressed: () =>
                              _abrirFormulario(docId: doc.id, dados: d),
                        ),
                        IconButton(
                          tooltip: 'Remover',
                          icon: Icon(Icons.delete_outline_rounded,
                              color: Colors.grey.shade600),
                          onPressed: () =>
                              _confirmarExclusao(doc.id, codigo),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }

  Widget _badge(String label, Color color) => Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(label,
            style: TextStyle(
                color: color,
                fontWeight: FontWeight.w700,
                fontSize: 11)),
      );

  Widget _infoSmall(IconData icon, String label) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: Colors.grey.shade500),
          const SizedBox(width: 4),
          Text(label,
              style: TextStyle(
                  fontSize: 12, color: Colors.grey.shade600)),
        ],
      );
}
