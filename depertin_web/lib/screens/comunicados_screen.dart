import 'dart:math' show min;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:depertin_web/theme/painel_admin_theme.dart';
import 'package:depertin_web/widgets/botao_suporte_flutuante.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class ComunicadosScreen extends StatefulWidget {
  const ComunicadosScreen({super.key});

  @override
  State<ComunicadosScreen> createState() => _ComunicadosScreenState();
}

class _ComunicadosScreenState extends State<ComunicadosScreen> {
  static const _roxo = PainelAdminTheme.roxo;
  static const _laranja = PainelAdminTheme.laranja;

  final _tipos = <String, Map<String, dynamic>>{
    'info': {'label': 'Informação', 'cor': const Color(0xFF1D4ED8), 'icon': Icons.info_rounded},
    'aviso': {'label': 'Aviso', 'cor': const Color(0xFFB45309), 'icon': Icons.warning_amber_rounded},
    'promo': {'label': 'Promoção', 'cor': const Color(0xFF15803D), 'icon': Icons.local_offer},
    'manutencao': {'label': 'Manutenção', 'cor': const Color(0xFFB91C1C), 'icon': Icons.build_rounded},
  };

  void _abrirFormulario({String? docId, Map<String, dynamic>? dados}) {
    final isEdit = docId != null;
    final tituloC = TextEditingController(text: isEdit ? dados!['titulo'] ?? '' : '');
    final mensagemC = TextEditingController(text: isEdit ? dados!['mensagem'] ?? '' : '');
    String tipo = isEdit ? (dados!['tipo'] ?? 'info') : 'info';
    String publico = isEdit ? (dados!['publico_alvo'] ?? 'todos') : 'todos';
    DateTime? expiracao = isEdit && dados!['data_expiracao'] != null
        ? (dados['data_expiracao'] as Timestamp).toDate()
        : null;
    bool ativo = isEdit ? (dados!['ativo'] ?? true) : true;
    var loading = false;

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.45),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) {
          final w = min(500.0, MediaQuery.sizeOf(ctx).width - 40);

          final dec = InputDecoration(
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

          Future<void> salvar() async {
            if (tituloC.text.trim().isEmpty || mensagemC.text.trim().isEmpty) {
              ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
                  content: Text('Preencha título e mensagem.')));
              return;
            }
            setS(() => loading = true);
            try {
              final d = <String, dynamic>{
                'titulo': tituloC.text.trim(),
                'mensagem': mensagemC.text.trim(),
                'tipo': tipo,
                'publico_alvo': publico,
                'ativo': ativo,
                if (expiracao != null)
                  'data_expiracao': Timestamp.fromDate(expiracao!),
                if (!isEdit) 'data_criacao': FieldValue.serverTimestamp(),
                if (isEdit) 'data_atualizacao': FieldValue.serverTimestamp(),
              };
              final col =
                  FirebaseFirestore.instance.collection('comunicados');
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
                  _header(isEdit ? 'Editar comunicado' : 'Novo comunicado'),
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(22, 20, 22, 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          DropdownButtonFormField<String>(
                            value: tipo,
                            decoration: dec.copyWith(labelText: 'Tipo'),
                            items: _tipos.entries
                                .map((e) => DropdownMenuItem(
                                      value: e.key,
                                      child: Row(children: [
                                        Icon(e.value['icon'] as IconData,
                                            size: 16,
                                            color: e.value['cor'] as Color),
                                        const SizedBox(width: 8),
                                        Text(e.value['label'] as String),
                                      ]),
                                    ))
                                .toList(),
                            onChanged: (v) => setS(() => tipo = v!),
                          ),
                          const SizedBox(height: 16),
                          DropdownButtonFormField<String>(
                            value: publico,
                            decoration: dec.copyWith(labelText: 'Público-alvo'),
                            items: const [
                              DropdownMenuItem(
                                  value: 'todos',
                                  child: Text('Todos os usuários')),
                              DropdownMenuItem(
                                  value: 'cliente', child: Text('Clientes')),
                              DropdownMenuItem(
                                  value: 'lojista', child: Text('Lojistas')),
                              DropdownMenuItem(
                                  value: 'entregador',
                                  child: Text('Entregadores')),
                            ],
                            onChanged: (v) => setS(() => publico = v!),
                          ),
                          const SizedBox(height: 16),
                          TextField(
                            controller: tituloC,
                            maxLength: 80,
                            decoration:
                                dec.copyWith(labelText: 'Título (até 80 caracteres)'),
                          ),
                          const SizedBox(height: 16),
                          TextField(
                            controller: mensagemC,
                            maxLines: 4,
                            maxLength: 500,
                            decoration: dec.copyWith(
                              labelText: 'Mensagem',
                              alignLabelWithHint: true,
                            ),
                          ),
                          const SizedBox(height: 8),
                          InkWell(
                            onTap: () async {
                              final d = await showDatePicker(
                                context: ctx,
                                initialDate: expiracao ??
                                    DateTime.now()
                                        .add(const Duration(days: 7)),
                                firstDate: DateTime.now(),
                                lastDate: DateTime.now()
                                    .add(const Duration(days: 365)),
                              );
                              if (d != null) setS(() => expiracao = d);
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
                                  Icon(Icons.event_outlined,
                                      size: 18,
                                      color: Colors.grey.shade600),
                                  const SizedBox(width: 8),
                                  Text(
                                    expiracao != null
                                        ? 'Expira em: ${DateFormat('dd/MM/yyyy').format(expiracao!)}'
                                        : 'Sem data de expiração',
                                    style: TextStyle(
                                        color: Colors.grey.shade700,
                                        fontSize: 14),
                                  ),
                                  const Spacer(),
                                  if (expiracao != null)
                                    GestureDetector(
                                      onTap: () =>
                                          setS(() => expiracao = null),
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
                            title: const Text('Comunicado ativo'),
                            subtitle: Text(ativo
                                ? 'Visível no app'
                                : 'Oculto no app'),
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
                                      strokeWidth: 2,
                                      color: Colors.white))
                              : const Icon(Icons.check_rounded, size: 20),
                          label: Text(loading
                              ? 'Salvando…'
                              : isEdit
                                  ? 'Salvar'
                                  : 'Publicar'),
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

  Widget _header(String titulo) => Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(22, 20, 22, 18),
        decoration: BoxDecoration(
          gradient: LinearGradient(
              colors: [
                _roxo.withValues(alpha: 0.09),
                _roxo.withValues(alpha: 0.03)
              ]),
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
              child: const Icon(Icons.message, color: _roxo, size: 22),
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
                        Text('Comunicados no App',
                            style: TextStyle(
                                fontSize: 26,
                                fontWeight: FontWeight.w800,
                                color: _roxo,
                                letterSpacing: -0.5)),
                        SizedBox(height: 6),
                        Text(
                          'Publique avisos, promoções e informações visíveis no app para os usuários.',
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
                    label: const Text('Novo comunicado'),
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
          .collection('comunicados')
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
                Icon(Icons.message,
                    size: 56, color: _roxo.withValues(alpha: 0.3)),
                const SizedBox(height: 16),
                Text('Nenhum comunicado publicado.',
                    style: TextStyle(
                        fontSize: 16, color: Colors.grey.shade600)),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _abrirFormulario,
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Criar primeiro comunicado'),
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
                final tipo = d['tipo']?.toString() ?? 'info';
                final tipoData = _tipos[tipo] ?? _tipos['info']!;
                final cor = tipoData['cor'] as Color;
                final icon = tipoData['icon'] as IconData;
                final titulo = d['titulo']?.toString() ?? '';
                final mensagem = d['mensagem']?.toString() ?? '';
                final publico = d['publico_alvo']?.toString() ?? 'todos';
                final ativo = d['ativo'] ?? true;
                final expiracao = d['data_expiracao'] as Timestamp?;
                final expirado = expiracao != null &&
                    expiracao.toDate().isBefore(DateTime.now());
                final ts = d['data_criacao'] as Timestamp?;
                final data = ts != null
                    ? DateFormat('dd/MM/yyyy').format(ts.toDate())
                    : '—';

                return Material(
                  color: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                    side: BorderSide(
                        color: !ativo || expirado
                            ? Colors.grey.shade200
                            : cor.withValues(alpha: 0.3)),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: cor.withValues(
                                alpha: ativo && !expirado ? 0.12 : 0.05),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(icon,
                              color: ativo && !expirado
                                  ? cor
                                  : Colors.grey.shade400,
                              size: 22),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(titulo,
                                        style: TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 15,
                                          color: ativo && !expirado
                                              ? Colors.black87
                                              : Colors.grey.shade500,
                                        )),
                                  ),
                                  if (expirado)
                                    _badge('EXPIRADO',
                                        const Color(0xFFB91C1C))
                                  else if (!ativo)
                                    _badge('INATIVO', Colors.grey.shade600)
                                  else
                                    _badge('ATIVO', const Color(0xFF15803D)),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(mensagem,
                                  style: TextStyle(
                                      fontSize: 13,
                                      color: Colors.grey.shade600,
                                      height: 1.4),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 10,
                                children: [
                                  _chip(Icons.people_outline_rounded,
                                      _labelPublico(publico)),
                                  _chip(Icons.calendar_today_outlined, data),
                                  if (expiracao != null && !expirado)
                                    _chip(
                                        Icons.event_outlined,
                                        'Expira ${DateFormat('dd/MM/yy').format(expiracao.toDate())}'),
                                ],
                              ),
                            ],
                          ),
                        ),
                        Switch(
                          value: ativo,
                          activeColor: _laranja,
                          onChanged: (v) => FirebaseFirestore.instance
                              .collection('comunicados')
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
                              color: Colors.grey.shade500),
                          onPressed: () => _confirmarExclusao(doc.id),
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

  String _labelPublico(String p) {
    switch (p) {
      case 'cliente':
        return 'Clientes';
      case 'lojista':
        return 'Lojistas';
      case 'entregador':
        return 'Entregadores';
      default:
        return 'Todos';
    }
  }

  Widget _badge(String label, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
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

  Widget _chip(IconData icon, String label) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: Colors.grey.shade500),
          const SizedBox(width: 4),
          Text(label,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
        ],
      );

  Future<void> _confirmarExclusao(String docId) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Row(children: [
          Icon(Icons.warning_amber_rounded, color: _laranja),
          const SizedBox(width: 12),
          const Expanded(
              child: Text('Remover comunicado',
                  style: TextStyle(fontWeight: FontWeight.w700))),
        ]),
        content: const Text('Este comunicado será removido permanentemente.'),
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
      await FirebaseFirestore.instance
          .collection('comunicados')
          .doc(docId)
          .delete();
    }
  }
}
