part of '../assinaturas_inadimplencia_screen.dart';

// ─── Central de Cobranças Modal ─────────────────────────────────────────────

class _CentralCobrancasModal extends StatefulWidget {
  const _CentralCobrancasModal({required this.itens, required this.onEnviar});

  final List<di.InadimplenciaItem> itens;
  final Future<void> Function(
    List<di.InadimplenciaItem> selecionados,
    List<String> canais,
    String mensagem,
  )
  onEnviar;

  @override
  State<_CentralCobrancasModal> createState() => _CentralCobrancasModalState();
}

class _CentralCobrancasModalState extends State<_CentralCobrancasModal> {
  final _selecionados = <String>{};
  final _canais = <String>{'email'};
  final _msgCtrl = TextEditingController();
  bool _enviando = false;

  @override
  void dispose() {
    _msgCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final largura = MediaQuery.of(context).size.width;
    final isMobile = largura < 700;
    final canais = ['email', 'whatsapp', 'sms', 'push'];
    final labelCanal = {
      'email': 'E-mail',
      'whatsapp': 'WhatsApp',
      'sms': 'SMS',
      'push': 'Push',
    };
    final iconCanal = {
      'email': Icons.email_rounded,
      'whatsapp': Icons.chat_rounded,
      'sms': Icons.sms_rounded,
      'push': Icons.notifications_rounded,
    };

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      insetPadding: const EdgeInsets.all(24),
      child: Container(
        width: isMobile ? largura - 48 : 640,
        constraints: const BoxConstraints(maxHeight: 700),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header gradiente
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF6A1B9A), Color(0xFF8E24AA)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(24),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.send_to_mobile_rounded,
                      color: Colors.white,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Central de Cobranças',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${widget.itens.length} cliente(s) inadimplente(s)',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.white.withOpacity(0.8),
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded, color: Colors.white),
                  ),
                ],
              ),
            ),

            // Conteúdo
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Checkbox(
                          value: _selecionados.length == widget.itens.length,
                          tristate:
                              _selecionados.isNotEmpty &&
                              _selecionados.length < widget.itens.length,
                          onChanged: (v) {
                            setState(() {
                              if (v == true) {
                                _selecionados.addAll(
                                  widget.itens.map((i) => i.cobrancaId),
                                );
                              } else {
                                _selecionados.clear();
                              }
                            });
                          },
                          activeColor: const Color(0xFF6A1B9A),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Selecionar todos (${widget.itens.length})',
                          style: const TextStyle(
                            fontWeight: FontWeight.w500,
                            color: Color(0xFF1A1A2E),
                          ),
                        ),
                        const Spacer(),
                        Text(
                          '${_selecionados.length} selecionado(s)',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF64748B),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    Container(
                      constraints: const BoxConstraints(maxHeight: 200),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8F7FC),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: ListView.separated(
                        shrinkWrap: true,
                        padding: const EdgeInsets.all(8),
                        itemCount: widget.itens.length.clamp(0, 20),
                        separatorBuilder: (_, _a) =>
                            const Divider(height: 1, indent: 8, endIndent: 8),
                        itemBuilder: (context, i) {
                          final item = widget.itens[i];
                          final isSelected = _selecionados.contains(
                            item.cobrancaId,
                          );
                          return InkWell(
                            onTap: () {
                              setState(() {
                                if (isSelected) {
                                  _selecionados.remove(item.cobrancaId);
                                } else {
                                  _selecionados.add(item.cobrancaId);
                                }
                              });
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                vertical: 6,
                                horizontal: 4,
                              ),
                              child: Row(
                                children: [
                                  Checkbox(
                                    value: isSelected,
                                    onChanged: (v) {
                                      setState(() {
                                        if (v == true) {
                                          _selecionados.add(item.cobrancaId);
                                        } else {
                                          _selecionados.remove(item.cobrancaId);
                                        }
                                      });
                                    },
                                    activeColor: const Color(0xFF6A1B9A),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    visualDensity: VisualDensity.compact,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      item.cobranca.clienteNome,
                                      style: const TextStyle(
                                        fontSize: 13,
                                        color: Color(0xFF1A1A2E),
                                      ),
                                    ),
                                  ),
                                  Text(
                                    fmtMoeda(item.cobranca.valor),
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: Color(0xFFF04438),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 20),

                    const Text(
                      'Canais de envio',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF1A1A2E),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: canais.map((c) {
                        final ativo = _canais.contains(c);
                        return FilterChip(
                          label: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                iconCanal[c],
                                size: 16,
                                color: ativo
                                    ? Colors.white
                                    : const Color(0xFF64748B),
                              ),
                              const SizedBox(width: 6),
                              Text(labelCanal[c] ?? c),
                            ],
                          ),
                          selected: ativo,
                          onSelected: (v) {
                            setState(() {
                              if (v) {
                                _canais.add(c);
                              } else {
                                _canais.remove(c);
                              }
                            });
                          },
                          selectedColor: const Color(0xFF6A1B9A),
                          checkmarkColor: Colors.white,
                          backgroundColor: const Color(0xFFF8F7FC),
                          labelStyle: TextStyle(
                            fontSize: 13,
                            color: ativo
                                ? Colors.white
                                : const Color(0xFF1A1A2E),
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                            side: BorderSide(
                              color: ativo
                                  ? const Color(0xFF6A1B9A)
                                  : Colors.grey.shade300,
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 16),

                    TextField(
                      controller: _msgCtrl,
                      decoration: InputDecoration(
                        hintText: 'Mensagem personalizada (opcional)',
                        filled: true,
                        fillColor: const Color(0xFFF8F7FC),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.all(16),
                      ),
                      maxLines: 3,
                      style: const TextStyle(fontSize: 14),
                    ),
                  ],
                ),
              ),
            ),

            // Footer
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: Colors.grey.shade200)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancelar'),
                  ),
                  const SizedBox(width: 12),
                  FilledButton.icon(
                    onPressed: _selecionados.isEmpty || _enviando
                        ? null
                        : _enviar,
                    icon: _enviando
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.send_rounded, size: 18),
                    label: Text(
                      _enviando
                          ? 'Enviando...'
                          : 'Enviar para ${_selecionados.length} cliente(s)',
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF6A1B9A),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _enviar() async {
    setState(() => _enviando = true);
    try {
      final selecionados = widget.itens
          .where((i) => _selecionados.contains(i.cobrancaId))
          .toList();
      await widget.onEnviar(
        selecionados,
        _canais.toList(),
        _msgCtrl.text.trim(),
      );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao enviar: $e'),
            backgroundColor: const Color(0xFFF04438),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }
}
