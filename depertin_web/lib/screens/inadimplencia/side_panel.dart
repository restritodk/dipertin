part of '../assinaturas_inadimplencia_screen.dart';

// ─── Painel Lateral ─────────────────────────────────────────────────────────

class _SidePanel extends StatefulWidget {
  const _SidePanel({
    required this.item,
    required this.onClose,
  });

  final di.InadimplenciaItem item;
  final VoidCallback onClose;

  @override
  State<_SidePanel> createState() => _SidePanelState();
}

class _SidePanelState extends State<_SidePanel> {
  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final c = item.cobranca;
    final cl = item.cliente;
    final altura = MediaQuery.of(context).size.height;

    return Container(
      height: altura * 0.9,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          // Alça de arrasto
          Container(
            margin: const EdgeInsets.only(top: 8),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 12, 0),
            child: Row(
              children: [
                // Logo
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: const Color(0xFF6A1B9A).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Center(
                    child: Text(
                      (cl?.storeName ?? c.clienteNome)
                          .substring(0, 1)
                          .toUpperCase(),
                      style: const TextStyle(
                        color: Color(0xFF6A1B9A),
                        fontWeight: FontWeight.w700,
                        fontSize: 18,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        cl?.storeName ?? c.clienteNome,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF1A1A2E),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          _buildBadge(
                            label: item.statusExibicao,
                            cor: statusExibicaoCor(item.statusExibicao),
                            fundo:
                                statusExibicaoFundo(item.statusExibicao),
                            fontSize: 10,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '${item.diasEmAtraso} dias em atraso',
                            style: const TextStyle(
                              fontSize: 12,
                              color: const Color(0xFFF04438),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: widget.onClose,
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
          ),

          const Divider(height: 24),

          // Conteúdo scrollável
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Resumo financeiro
                  _buildSectionTitle('Resumo Financeiro'),
                  const SizedBox(height: 12),
                  _cardWrapper(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          _infoRow('Valor em atraso',
                              fmtMoeda(c.valor), cor: const Color(0xFFF04438)),
                          const Divider(height: 20),
                          _infoRow('Próximo vencimento', fmtData(c.vencimento)),
                          const Divider(height: 20),
                          _infoRow('Dias em atraso',
                              '${item.diasEmAtraso} dias',
                              cor: const Color(0xFFF04438)),
                          const Divider(height: 20),
                          _infoRow('Risco',
                              riscoRotulo(item.risco).toUpperCase(),
                              cor: riscoCor(item.risco)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Dados do cliente
                  _buildSectionTitle('Dados do Cliente'),
                  const SizedBox(height: 12),
                  _cardWrapper(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          _infoRow('Cidade', cl?.addressCity ?? '—'),
                          const Divider(height: 16),
                          _infoRow('UF', cl?.addressState ?? '—'),
                          const Divider(height: 16),
                          _infoRow('Telefone', cl?.phone ?? '—'),
                          const Divider(height: 16),
                          _infoRow('E-mail', c.clienteEmail),
                          const Divider(height: 16),
                          _infoRow('Último acesso',
                              cl?.lastPaymentDateExibir ?? '—'),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Plano e módulos
                  _buildSectionTitle('Plano Contratado'),
                  const SizedBox(height: 12),
                  _cardWrapper(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              _buildBadge(
                                label: c.planoNome.isNotEmpty
                                    ? c.planoNome
                                    : '—',
                                cor: const Color(0xFF6A1B9A),
                                fundo: const Color(0xFFF1E9FF),
                              ),
                              const Spacer(),
                              Text(
                                fmtMoeda(c.valor),
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF1A1A2E),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              _buildBadge(
                                label: c.modulo.rotulo,
                                cor: c.modulo.cor,
                                fundo: c.modulo.fundo,
                              ),
                              if (cl != null && cl.modulosExtras.isNotEmpty)
                                ...cl.modulosExtras.map((m) {
                                  final mod = ModuloCobranca.fromCodigo(m);
                                  return _buildBadge(
                                    label: mod.rotulo,
                                    cor: mod.cor,
                                    fundo: mod.fundo,
                                  );
                                }),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Próxima ação (régua inteligente)
                  _buildSectionTitle('Próxima Ação'),
                  const SizedBox(height: 12),
                  _cardWrapper(
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            const Color(0xFF6A1B9A).withOpacity(0.05),
                            Colors.white,
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: const Color(0xFF6A1B9A)
                                  .withOpacity(0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(
                              Icons.tips_and_updates_rounded,
                              color: Color(0xFF6A1B9A),
                              size: 22,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _proximaAcao(item),
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF1A1A2E),
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Automático · Régua de cobrança',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey.shade500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Régua de cobrança (timeline)
                  _buildSectionTitle('Histórico / Régua de Cobrança'),
                  const SizedBox(height: 12),
                  ..._buildTimeline(cl),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: Color(0xFF1A1A2E),
      ),
    );
  }

  Widget _infoRow(String label, String value, {Color? cor}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style: const TextStyle(
                fontSize: 13, color: Color(0xFF64748B))),
        Text(
          value,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: cor ?? const Color(0xFF1A1A2E),
          ),
        ),
      ],
    );
  }

  String _proximaAcao(di.InadimplenciaItem item) {
    final dias = item.diasEmAtraso;
    if (dias <= 0) return 'Nenhuma ação necessária no momento.';
    if (dias <= 3) return 'Enviar lembrete de cobrança nas próximas 24h.';
    if (dias <= 7) {
      return 'Enviar notificação via WhatsApp e SMS amanhã às 09:00.';
    }
    if (dias <= 15) {
      return 'Enviar 2ª via por e-mail e contato telefônico.';
    }
    if (dias <= 30) {
      return 'Notificar sobre suspensão em ${30 - dias} dias.';
    }
    return 'Suspender todos os módulos imediatamente.';
  }

  List<Widget> _buildTimeline(ClienteAssinaturaModel? cl) {
    if (cl == null) {
      return [
        _timelineItem(
          Icons.info_outline_rounded,
          'Sem histórico disponível',
          '—',
          Colors.grey,
        ),
      ];
    }

    final eventos = cl.historico;
    if (eventos.isEmpty) {
      return [
        _timelineItem(
          Icons.add_circle_outline_rounded,
          'Cobrança criada',
          cl.createdAtExibir,
          const Color(0xFF6A1B9A),
          primeiro: true,
        ),
      ];
    }

    final etapas = <Widget>[];

    // Cobrança criada
    etapas.add(_timelineItem(
      Icons.add_circle_rounded,
      'Cobrança criada',
      cl.createdAtExibir,
      const Color(0xFF6A1B9A),
      primeiro: true,
    ));

    for (final evt in eventos) {
      IconData icon;
      Color cor;
      switch (evt.tipo) {
        case 'cobranca':
          icon = Icons.send_rounded;
          cor = const Color(0xFF0EA5E9);
          break;
        case 'email':
          icon = Icons.email_rounded;
          cor = const Color(0xFF0EA5E9);
          break;
        case 'whatsapp':
          icon = Icons.chat_rounded;
          cor = const Color(0xFF16A34A);
          break;
        case 'sms':
          icon = Icons.sms_rounded;
          cor = const Color(0xFFFF8F00);
          break;
        case 'bloqueio':
          icon = Icons.block_rounded;
          cor = const Color(0xFFF04438);
          break;
        case 'desbloqueio':
          icon = Icons.check_circle_rounded;
          cor = const Color(0xFF16A34A);
          break;
        case 'pagamento':
          icon = Icons.payments_rounded;
          cor = const Color(0xFF16A34A);
          break;
        default:
          icon = Icons.circle_rounded;
          cor = const Color(0xFF94A3B8);
      }

      etapas.add(_timelineItem(
        icon,
        evt.descricao,
        evt.dataExibir,
        cor,
      ));
    }

    // Estado atual
    if (cl.status == 'suspenso') {
      etapas.add(_timelineItem(
        Icons.block_rounded,
        'Suspensão',
        cl.blockedAtExibir,
        const Color(0xFFF04438),
      ));
    }

    return etapas;
  }

  Widget _timelineItem(
    IconData icon,
    String descricao,
    String data,
    Color cor, {
    bool primeiro = false,
  }) {
    return Padding(
      padding: EdgeInsets.only(left: 8, top: primeiro ? 0 : 0),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Linha vertical + bolinha
            SizedBox(
              width: 32,
              child: Column(
                children: [
                  if (!primeiro)
                    Container(
                      width: 2,
                      height: 8,
                      color: cor.withOpacity(0.3),
                    )
                  else
                    const SizedBox(height: 8),
                  Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      color: cor.withOpacity(0.15),
                      shape: BoxShape.circle,
                      border: Border.all(color: cor, width: 2),
                    ),
                    child: Icon(icon, size: 10, color: cor),
                  ),
                  Expanded(
                    child: Container(
                      width: 2,
                      color: cor.withOpacity(0.3),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            // Conteúdo
            Padding(
              padding: const EdgeInsets.only(bottom: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 6),
                  Text(
                    descricao,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF1A1A2E),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    data,
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF94A3B8),
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
}
