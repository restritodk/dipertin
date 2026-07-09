import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:depertin_web/services/firebase_functions_config.dart';
import 'package:depertin_web/theme/painel_admin_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

// =============================================================================
// Modal único para "Enviar Cobrança" (Pendências) e
// "Enviar Comprovante" (Recebimentos).
// =============================================================================

/// Abre o modal de envio de comunicação (cobrança ou comprovante).
///
/// [tipo] = "cobranca" | "comprovante"
/// [clienteId] = ID do cliente na subcoleção clientes_comercial
/// [clienteNome] = nome para exibição
/// [valorExtra] = valor adicional a exibir (ex: valor recebido no comprovante)
/// [formaPagamentoExtra] = forma de pagamento (para comprovante)
/// [dataExtra] = data adicional (ex: data do pagamento no comprovante)
Future<void> abrirModalEnviarComunicacao({
  required BuildContext context,
  required String lojaId,
  required String tipo,
  required String clienteId,
  required String clienteNome,
  String? clienteTelefone,
  String? clienteWhatsApp,
  String? clienteEmail,
  double? valorExtra,
  String? formaPagamentoExtra,
  DateTime? dataExtra,
}) {
  return showDialog(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => _EnviarComunicacaoModal(
      lojaId: lojaId,
      tipo: tipo,
      clienteId: clienteId,
      clienteNome: clienteNome,
      clienteTelefone: clienteTelefone,
      clienteWhatsApp: clienteWhatsApp,
      clienteEmail: clienteEmail,
      valorExtra: valorExtra,
      formaPagamentoExtra: formaPagamentoExtra,
      dataExtra: dataExtra,
    ),
  );
}

// =============================================================================
// STATE
// =============================================================================

class _EnviarComunicacaoModal extends StatefulWidget {
  const _EnviarComunicacaoModal({
    required this.lojaId,
    required this.tipo,
    required this.clienteId,
    required this.clienteNome,
    this.clienteTelefone,
    this.clienteWhatsApp,
    this.clienteEmail,
    this.valorExtra,
    this.formaPagamentoExtra,
    this.dataExtra,
  });

  final String lojaId;
  final String tipo;
  final String clienteId;
  final String clienteNome;
  final String? clienteTelefone;
  final String? clienteWhatsApp;
  final String? clienteEmail;
  final double? valorExtra;
  final String? formaPagamentoExtra;
  final DateTime? dataExtra;

  @override
  State<_EnviarComunicacaoModal> createState() =>
      _EnviarComunicacaoModalState();
}

class _EnviarComunicacaoModalState extends State<_EnviarComunicacaoModal> {
  bool _carregandoConfig = true;
  bool _enviando = false;
  String? _erro;

  // Canais ativos do Firebase
  final Map<String, bool> _canaisAtivos = {};
  final Map<String, String> _canaisLabels = {
    'whatsapp': 'WhatsApp',
    'sms': 'SMS',
    'email': 'E-mail',
  };
  final Map<String, IconData> _canaisIcones = {
    'whatsapp': Icons.chat_rounded,
    'sms': Icons.sms_rounded,
    'email': Icons.email_rounded,
  };
  final Map<String, Color> _canaisCores = {
    'whatsapp': const Color(0xFF25D366),
    'sms': const Color(0xFF6A1B9A),
    'email': const Color(0xFF2563EB),
  };

  // Canais selecionados
  final Set<String> _canaisSelecionados = {};

  // Dados do cliente (carregados do Firestore se não passados)
  String _clienteNome = '';
  String _clienteTelefone = '';
  String _clienteWhatsApp = '';
  String _clienteEmail = '';

  @override
  void initState() {
    super.initState();
    _clienteNome = widget.clienteNome;
    _clienteTelefone = widget.clienteTelefone ?? '';
    _clienteWhatsApp = widget.clienteWhatsApp ?? '';
    _clienteEmail = widget.clienteEmail ?? '';
    _carregarDados();
  }

  Future<void> _carregarDados() async {
    try {
      // Carregar configurações comerciais para saber canais ativos
      final configDoc = await FirebaseFirestore.instance
          .collection('gestao_comercial_configuracoes')
          .doc(widget.lojaId)
          .get();

      final configData = configDoc.data() ?? {};
      final cobrancaMap = configData['cobranca'] as Map<String, dynamic>? ?? {};
      final emailMap = cobrancaMap['email'] as Map<String, dynamic>? ?? {};

      // Verificar quais canais estão ativos na config
      for (final canal in ['whatsapp', 'sms', 'email']) {
        bool ativo = false;
        if (canal == 'whatsapp') {
          final w = cobrancaMap['whatsapp'] as Map<String, dynamic>? ?? {};
          ativo = w['ativo'] == true && (w['apiUrl']?.toString().trim().isNotEmpty ?? false);
        } else if (canal == 'sms') {
          final s = cobrancaMap['sms'] as Map<String, dynamic>? ?? {};
          ativo = s['ativo'] == true && (s['apiUrl']?.toString().trim().isNotEmpty ?? false);
        } else if (canal == 'email') {
          // Email usa o emailTransacional config
          final et = emailMap['emailTransacional'] as Map<String, dynamic>? ?? {};
          final modo = (et['modoIntegracao'] ?? '').toString().trim();
          ativo = modo.isNotEmpty;
        }
        _canaisAtivos[canal] = ativo;
      }

      // Buscar dados do cliente em múltiplas fontes
      await _carregarDadosCliente();

      // Selecionar todos os canais ativos por padrão
      for (final entry in _canaisAtivos.entries) {
        if (entry.value) {
          _canaisSelecionados.add(entry.key);
        }
      }

      if (mounted) {
        setState(() {
          _carregandoConfig = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _carregandoConfig = false;
          _erro = 'Erro ao carregar configurações: $e';
        });
      }
    }
  }

  /// Extrai o primeiro valor não-vazio de um map testando múltiplas chaves.
  /// Retorna null se nenhuma chave for encontrada.
  String? _extrairCampo(Map<String, dynamic>? data, List<String> chaves) {
    if (data == null) return null;
    for (final chave in chaves) {
      final v = data[chave];
      if (v != null && v.toString().trim().isNotEmpty) {
        return v.toString().trim();
      }
    }
    return null;
  }

  /// Busca dados do cliente em múltiplas fontes.
  Future<void> _carregarDadosCliente() async {
    if (_clienteTelefone.isNotEmpty && _clienteWhatsApp.isNotEmpty && _clienteEmail.isNotEmpty) {
      return;
    }

    final db = FirebaseFirestore.instance;
    final lojaId = widget.lojaId;
    final clienteId = widget.clienteId;

    // ── Fonte 1: clientes_comercial (sempre tenta, pois clienteId é o doc ID desta coleção) ──
    try {
      final cDoc = await db
          .collection('users').doc(lojaId)
          .collection('clientes_comercial').doc(clienteId)
          .get();
      if (cDoc.exists) {
        final cd = cDoc.data() ?? {};
        // Só sobrescreve nome se estiver vazio ou genérico
        if (_clienteNome.isEmpty || _clienteNome == 'Cliente') {
          _clienteNome = _extrairCampo(cd, ['nome', 'razao_social', 'nome_fantasia', 'cliente_nome']) ?? _clienteNome;
        }
        if (_clienteTelefone.isEmpty) {
          _clienteTelefone = _extrairCampo(cd, ['telefone', 'celular', 'contato', 'phone']) ?? '';
        }
        if (_clienteWhatsApp.isEmpty) {
          _clienteWhatsApp = _extrairCampo(cd, ['whatsapp', 'whatsApp', 'whats_app', 'telefone', 'celular']) ?? '';
        }
        if (_clienteEmail.isEmpty) {
          _clienteEmail = _extrairCampo(cd, ['email', 'Email', 'e_mail', 'email_cliente', 'cliente_email', 'email_contato']) ?? '';
        }
      }
    } catch (_) {}

    // ── Se ainda faltar email, tentar users/{clienteId} (conta Firebase) ──
    // NOTA: clienteId pode ser o UID real do Firebase Auth OU o doc ID
    // de clientes_comercial. Tentamos ambos.
    if (_clienteEmail.isEmpty) {
      try {
        final uDoc = await db.collection('users').doc(clienteId).get();
        if (uDoc.exists) {
          final ud = uDoc.data() ?? {};
          if (_clienteNome.isEmpty || _clienteNome == 'Cliente') {
            _clienteNome = _extrairCampo(ud, ['nome', 'nome_completo', 'displayName', 'name']) ?? _clienteNome;
          }
          if (_clienteEmail.isEmpty) {
            _clienteEmail = _extrairCampo(ud, ['email', 'Email', '_email', 'email_contato', 'email_cliente']) ?? '';
          }
          if (_clienteTelefone.isEmpty) {
            _clienteTelefone = _extrairCampo(ud, ['telefone', 'celular', 'phone', 'phoneNumber', 'telefone_contato']) ?? '';
          }
          if (_clienteWhatsApp.isEmpty) {
            _clienteWhatsApp = _extrairCampo(ud, ['whatsapp', 'whatsApp', 'telefone', 'celular']) ?? '';
          }
        }
      } catch (_) {}
    }
  }

  bool get _nenhumCanalAtivo =>
      _canaisAtivos.values.every((v) => v == false);

  void _toggleCanal(String canal) {
    setState(() {
      if (_canaisSelecionados.contains(canal)) {
        _canaisSelecionados.remove(canal);
      } else {
        _canaisSelecionados.add(canal);
      }
    });
  }

  /// Verifica se o cliente tem os dados necessários para cada canal selecionado.
  /// Retorna lista de avisos.
  List<String> _validarDadosCliente() {
    final avisos = <String>[];
    if (_canaisSelecionados.contains('whatsapp') && _clienteWhatsApp.isEmpty) {
      avisos.add('Cliente não possui WhatsApp cadastrado.');
    }
    if (_canaisSelecionados.contains('sms') && _clienteTelefone.isEmpty) {
      avisos.add('Cliente não possui telefone cadastrado.');
    }
    if (_canaisSelecionados.contains('email') && _clienteEmail.isEmpty) {
      avisos.add('Cliente não possui e-mail cadastrado.');
    }
    return avisos;
  }

  Future<void> _enviar() async {
    final avisos = _validarDadosCliente();
    if (avisos.isNotEmpty) {
      _mostrarAviso(avisos);
      return;
    }

    if (_canaisSelecionados.isEmpty) return;

    setState(() {
      _enviando = true;
      _erro = null;
    });

    try {
      final result = await callFirebaseFunctionSafe(
        'gestaoComercialEnviarComunicacao',
        region: kFirebaseFunctionsRegionSouth,
        parameters: {
          'lojaId': widget.lojaId,
          'clienteId': widget.clienteId,
          'tipo': widget.tipo,
          'canais': _canaisSelecionados.toList(),
        },
      );

      if (!mounted) return;

      final resultadoData = result;
      final resultados = resultadoData['resultados'] as List<dynamic>? ?? [];
      final linkPagamento = resultadoData['linkPagamento']?.toString() ?? '';

      // Montar resumo
      final sucessos = resultados.where((r) => r is Map && r['ok'] == true).toList();
      final falhas = resultados.where((r) => r is Map && r['ok'] != true).toList();

      final nomeTipo = widget.tipo == 'cobranca' ? 'cobrança' : 'comprovante';

      if (sucessos.isNotEmpty && falhas.isEmpty) {
        // Tudo ok — fecha o modal e mostra diálogo premium de sucesso
        _fechar();
        if (mounted) {
          final canaisUsados = sucessos.map((r) {
            final c = (r as Map)['canal']?.toString() ?? '';
            return _canaisLabels[c] ?? c;
          }).join(', ');
          _mostrarResultadoDialog(
            tipo: 'sucesso',
            mensagem: '$nomeTipo enviado com sucesso!',
            detalhes: 'Canais utilizados: $canaisUsados',
            linkPagamento: linkPagamento,
          );
        }
      } else if (sucessos.isNotEmpty && falhas.isNotEmpty) {
        // Parcial — fecha o modal e mostra diálogo premium de aviso
        _fechar();
        if (mounted) {
          final canaisSucesso = sucessos.map((r) {
            final c = (r as Map)['canal']?.toString() ?? '';
            return _canaisLabels[c] ?? c;
          }).join(', ');
          final detalheFalhas = falhas.map((r) {
            final m = r as Map;
            final c = _canaisLabels[m['canal']?.toString() ?? ''] ?? m['canal'];
            return '$c: ${m['erro'] ?? 'erro desconhecido'}';
          }).join('\n');
          _mostrarResultadoDialog(
            tipo: 'parcial',
            mensagem: '$nomeTipo enviado parcialmente',
            detalhes: 'Sucesso via: $canaisSucesso',
            erros: detalheFalhas,
            linkPagamento: linkPagamento,
          );
        }
      } else {
        // Tudo falhou — fecha o modal e mostra diálogo premium de erro
        _fechar();
        if (mounted) {
          final erros = falhas.map((r) {
            final m = r as Map;
            final c = _canaisLabels[m['canal']?.toString() ?? ''] ?? m['canal'];
            return '$c: ${m['erro'] ?? 'erro desconhecido'}';
          }).join('\n');
          _mostrarResultadoDialog(
            tipo: 'erro',
            mensagem: 'Falha ao enviar $nomeTipo',
            erros: erros,
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _enviando = false;
          _erro = 'Erro ao enviar: ${e.toString().replaceAll(RegExp(r'^\[.*?\] '), '')}';
        });
      }
    }
  }

  // ── Diálogo Premium de Resultado ──
  void _mostrarResultadoDialog({
    required String tipo,
    required String mensagem,
    String? detalhes,
    String? erros,
    String? linkPagamento,
  }) {
    if (!mounted) return;

    final bool isSuccess = tipo == 'sucesso';
    final bool isPartial = tipo == 'parcial';

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _PremiumResultadoDialog(
        isSuccess: isSuccess,
        isPartial: isPartial,
        mensagem: mensagem,
        detalhes: detalhes,
        erros: erros,
        linkPagamento: linkPagamento,
      ),
    );
  }

  void _mostrarAviso(List<String> avisos) {
    if (!mounted) return;
    final mensagem = avisos.join('\n');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.warning_amber_rounded, color: Colors.white, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                mensagem,
                style: const TextStyle(fontSize: 13),
              ),
            ),
          ],
        ),
        backgroundColor: const Color(0xFFEA580C),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
        duration: const Duration(seconds: 5),
      ),
    );
  }

  void _fechar() {
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final ehCobranca = widget.tipo == 'cobranca';
    final titulo = ehCobranca ? 'Enviar Cobrança' : 'Enviar Comprovante';
    final icone = ehCobranca ? Icons.send_rounded : Icons.receipt_long_rounded;
    final subtitulo = ehCobranca
        ? 'Selecione os canais para enviar a cobrança ao cliente'
        : 'Selecione os canais para enviar o comprovante ao cliente';

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 540, maxHeight: 720),
        child: Material(
          color: Colors.white,
          child: Column(
            children: [
              // ── Header ──
              _buildHeader(titulo, subtitulo, icone),

              // ── Body ──
              Expanded(
                child: _carregandoConfig
                    ? const Center(
                        child: CircularProgressIndicator(
                          color: PainelAdminTheme.roxo,
                        ),
                      )
                    : _buildBody(ehCobranca),
              ),

              // ── Footer ──
              _buildFooter(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(String titulo, String subtitulo, IconData icone) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 20, 8, 20),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF4A148C), Color(0xFF6A1B9A), Color(0xFF7B1FA2)],
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icone, color: Colors.white, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  titulo,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
                if (subtitulo.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    subtitulo,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 13,
                      color: Colors.white.withValues(alpha: 0.82),
                    ),
                  ),
                ],
              ],
            ),
          ),
          IconButton(
            onPressed: _enviando ? null : _fechar,
            icon: const Icon(Icons.close_rounded, color: Colors.white),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(bool ehCobranca) {
    if (_nenhumCanalAtivo) {
      return Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.warning_amber_rounded,
              size: 56,
              color: const Color(0xFFF59E0B).withValues(alpha: 0.6),
            ),
            const SizedBox(height: 20),
            Text(
              'Nenhum canal de comunicação está ativo.',
              textAlign: TextAlign.center,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF1A1A2E),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Ative WhatsApp, E-mail ou SMS nas Configurações Comerciais.',
              textAlign: TextAlign.center,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13,
                color: const Color(0xFF64748B),
              ),
            ),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Dados do cliente ──
          _buildSectionLabel('Dados do cliente'),
          const SizedBox(height: 12),
          _buildClienteCard(ehCobranca),
          const SizedBox(height: 24),

          // ── Canais disponíveis ──
          _buildSectionLabel('Canais de envio'),
          const SizedBox(height: 8),
          Text(
            'Selecione um ou mais canais para enviar a ${ehCobranca ? 'cobrança' : 'comprovante'}.',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 12,
              color: const Color(0xFF64748B),
            ),
          ),
          const SizedBox(height: 12),
          ..._buildCanaisList(),

          // ── Erro ──
          if (_erro != null) ...[
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF2F2),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFFECACA)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.error_outline_rounded,
                      color: Color(0xFFDC2626), size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _erro!,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 13,
                        color: const Color(0xFF991B1B),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSectionLabel(String label) {
    return Text(
      label,
      style: GoogleFonts.plusJakartaSans(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        color: const Color(0xFF1A1A2E),
        letterSpacing: 0.5,
      ),
    );
  }

  Widget _buildClienteCard(bool ehCobranca) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F7FC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE8E3F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Nome
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF6A1B9A), Color(0xFF8E24AA)],
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                alignment: Alignment.center,
                child: Text(
                  _clienteNome.isNotEmpty
                      ? _clienteNome.substring(0, 1).toUpperCase()
                      : '?',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _clienteNome,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF1A1A2E),
                      ),
                    ),
                    if (widget.valorExtra != null || ehCobranca) ...[
                      const SizedBox(height: 2),
                      Text(
                        ehCobranca
                            ? 'Pendência financeira'
                            : 'Pagamento recebido',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 12,
                          color: const Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Divider(height: 1, color: Color(0xFFE8E3F0)),
          const SizedBox(height: 14),

          // Informações adicionais
          if (ehCobranca) ...[
            _buildInfoRow(Icons.attach_money_rounded, 'Valor em aberto',
                widget.valorExtra != null
                    ? 'R\$ ${widget.valorExtra!.toStringAsFixed(2).replaceAll('.', ',')}'
                    : 'Consulte os detalhes'),
            if (widget.dataExtra != null)
              _buildInfoRow(
                Icons.calendar_today_rounded,
                'Vencimento',
                '${widget.dataExtra!.day.toString().padLeft(2, '0')}/'
                    '${widget.dataExtra!.month.toString().padLeft(2, '0')}/'
                    '${widget.dataExtra!.year}',
              ),
          ] else ...[
            if (widget.valorExtra != null)
              _buildInfoRow(Icons.attach_money_rounded, 'Valor recebido',
                  'R\$ ${widget.valorExtra!.toStringAsFixed(2).replaceAll('.', ',')}'),
            if (widget.formaPagamentoExtra != null &&
                widget.formaPagamentoExtra!.isNotEmpty)
              _buildInfoRow(
                  Icons.payments_rounded, 'Forma de pagamento', widget.formaPagamentoExtra!),
            if (widget.dataExtra != null)
              _buildInfoRow(
                Icons.calendar_today_rounded,
                'Data do pagamento',
                '${widget.dataExtra!.day.toString().padLeft(2, '0')}/'
                    '${widget.dataExtra!.month.toString().padLeft(2, '0')}/'
                    '${widget.dataExtra!.year}',
              ),
          ],

          // Contato
          const SizedBox(height: 8),
          if (_clienteTelefone.isNotEmpty)
            _buildInfoRow(Icons.phone_rounded, 'Telefone', _clienteTelefone),
          if (_clienteWhatsApp.isNotEmpty)
            _buildInfoRow(Icons.chat_rounded, 'WhatsApp', _clienteWhatsApp),
          if (_clienteEmail.isNotEmpty)
            _buildInfoRow(Icons.email_rounded, 'E-mail', _clienteEmail),
        ],
      ),
    );
  }

  Widget _buildInfoRow(IconData icone, String label, String valor) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Icon(icone, size: 15, color: const Color(0xFF64748B)),
          const SizedBox(width: 8),
          Text(
            '$label: ',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: const Color(0xFF64748B),
            ),
          ),
          Expanded(
            child: Text(
              valor,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF1A1A2E),
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildCanaisList() {
    return _canaisAtivos.entries
        .where((e) => e.value)
        .map((entry) {
      final canal = entry.key;
      final selecionado = _canaisSelecionados.contains(canal);
      final label = _canaisLabels[canal] ?? canal;
      final icone = _canaisIcones[canal] ?? Icons.circle;
      final cor = _canaisCores[canal] ?? const Color(0xFF64748B);

      // Verificar se cliente tem dados para este canal
      String? aviso;
      if (canal == 'whatsapp' && _clienteWhatsApp.isEmpty) {
        aviso = 'Cliente não possui WhatsApp cadastrado.';
      } else if (canal == 'sms' && _clienteTelefone.isEmpty) {
        aviso = 'Cliente não possui telefone cadastrado.';
      } else if (canal == 'email' && _clienteEmail.isEmpty) {
        aviso = 'Cliente não possui e-mail cadastrado.';
      }

      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: InkWell(
          onTap: aviso == null
              ? () => _toggleCanal(canal)
              : null,
          borderRadius: BorderRadius.circular(12),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: selecionado
                  ? cor.withValues(alpha: 0.08)
                  : Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: selecionado
                    ? cor.withValues(alpha: 0.5)
                    : aviso != null
                        ? const Color(0xFFFECACA)
                        : const Color(0xFFE2E8F0),
                width: selecionado ? 1.5 : 1,
              ),
            ),
            child: Row(
              children: [
                // Checkbox / Ícone
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: aviso != null
                        ? const Color(0xFFFEF2F2)
                        : selecionado
                            ? cor
                            : Colors.transparent,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: aviso != null
                          ? const Color(0xFFFECACA)
                          : selecionado
                              ? cor
                              : const Color(0xFFCBD5E1),
                      width: selecionado ? 0 : 1.5,
                    ),
                  ),
                  child: aviso != null
                      ? const Icon(Icons.warning_amber_rounded,
                          size: 14, color: Color(0xFFDC2626))
                      : selecionado
                          ? const Icon(Icons.check_rounded,
                              size: 16, color: Colors.white)
                          : null,
                ),
                const SizedBox(width: 12),
                // Ícone do canal
                Icon(icone, size: 20, color: cor),
                const SizedBox(width: 10),
                // Label
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF1A1A2E),
                        ),
                      ),
                      if (aviso != null)
                        Text(
                          aviso,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 11,
                            color: const Color(0xFFDC2626),
                          ),
                        )
                      else
                        Text(
                          selecionado ? 'Selecionado' : 'Clique para selecionar',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 11,
                            color: selecionado
                                ? const Color(0xFF16A34A)
                                : const Color(0xFF94A3B8),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }).toList();
  }

  Widget _buildFooter() {
    if (_nenhumCanalAtivo) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
        child: SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            onPressed: _fechar,
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: Color(0xFFE2E8F0)),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text('Fechar'),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0xFFF1F5F9))),
      ),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: _enviando ? null : _fechar,
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Color(0xFFE2E8F0)),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                'Cancelar',
                style: TextStyle(color: Color(0xFF64748B)),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: FilledButton(
              onPressed: (_enviando || _canaisSelecionados.isEmpty)
                  ? null
                  : _enviar,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF6A1B9A),
                disabledBackgroundColor: const Color(0xFFE2E8F0),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: _enviando
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Colors.white,
                      ),
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.send_rounded, size: 18),
                        const SizedBox(width: 8),
                        Text(
                          _canaisSelecionados.length > 1
                              ? 'Enviar via ${_canaisSelecionados.length} canais'
                              : 'Enviar',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// Diálogo Premium de Resultado do Envio
// =============================================================================

class _PremiumResultadoDialog extends StatefulWidget {
  final bool isSuccess;
  final bool isPartial;
  final String mensagem;
  final String? detalhes;
  final String? erros;
  final String? linkPagamento; // link gerado para cobrança

  const _PremiumResultadoDialog({
    required this.isSuccess,
    required this.isPartial,
    required this.mensagem,
    this.detalhes,
    this.erros,
    this.linkPagamento,
  });

  @override
  State<_PremiumResultadoDialog> createState() =>
      _PremiumResultadoDialogState();
}

class _PremiumResultadoDialogState extends State<_PremiumResultadoDialog>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _scaleAnim;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _scaleAnim = CurvedAnimation(
      parent: _animController,
      curve: const Interval(0.0, 0.5, curve: Curves.easeOutBack),
    );
    _fadeAnim = CurvedAnimation(
      parent: _animController,
      curve: const Interval(0.3, 1.0, curve: Curves.easeIn),
    );
    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isSuccess = widget.isSuccess;
    final isPartial = widget.isPartial;

    final Color corPrimaria =
        isSuccess ? const Color(0xFF16A34A) : (isPartial ? const Color(0xFFEA580C) : const Color(0xFFDC2626));
    final Color corFundo =
        isSuccess ? const Color(0xFFF0FDF4) : (isPartial ? const Color(0xFFFFF7ED) : const Color(0xFFFEF2F2));
    final IconData icone =
        isSuccess ? Icons.check_circle_rounded : (isPartial ? Icons.warning_amber_rounded : Icons.error_outline_rounded);
    final String rotulo =
        isSuccess ? 'Enviado' : (isPartial ? 'Envio parcial' : 'Falha no envio');

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      clipBehavior: Clip.antiAlias,
      child: AnimatedBuilder(
        animation: _animController,
        builder: (ctx, child) => Transform.scale(
          scale: _scaleAnim.value,
          child: Opacity(
            opacity: _fadeAnim.value,
            child: child,
          ),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Material(
            color: Colors.white,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // ── Header gradiente ──
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(24, 32, 24, 28),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: isSuccess
                          ? [const Color(0xFF16A34A), const Color(0xFF22C55E)]
                          : isPartial
                              ? [const Color(0xFFEA580C), const Color(0xFFF97316)]
                              : [const Color(0xFFDC2626), const Color(0xFFEF4444)],
                    ),
                  ),
                  child: Column(
                    children: [
                      // Ícone decorativo
                      Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(icone, color: Colors.white, size: 36),
                      ),
                      const SizedBox(height: 16),
                      // Label
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          rotulo,
                          style: GoogleFonts.plusJakartaSans(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      // Mensagem principal
                      Text(
                        widget.mensagem,
                        textAlign: TextAlign.center,
                        style: GoogleFonts.plusJakartaSans(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),

                // ── Corpo ──
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Detalhes (sucesso)
                      if (widget.detalhes != null && widget.detalhes!.isNotEmpty) ...[
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: corFundo,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: corPrimaria.withValues(alpha: 0.2),
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.info_outline_rounded,
                                  color: corPrimaria, size: 18),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  widget.detalhes!,
                                  style: GoogleFonts.plusJakartaSans(
                                    color: corPrimaria,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],

                      // Erros detalhados
                      if (widget.erros != null && widget.erros!.isNotEmpty) ...[
                        if (widget.detalhes != null && widget.detalhes!.isNotEmpty)
                          const SizedBox(height: 12),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFEF2F2),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFFECACA)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.error_outline_rounded,
                                      color: Color(0xFFDC2626), size: 16),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Detalhes do erro:',
                                    style: GoogleFonts.plusJakartaSans(
                                      color: const Color(0xFFDC2626),
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                widget.erros!,
                                style: GoogleFonts.plusJakartaSans(
                                  color: const Color(0xFF7F1D1D),
                                  fontSize: 12,
                                  height: 1.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],

                      // Link de pagamento (cobrança)
                      if (widget.linkPagamento != null && widget.linkPagamento!.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEDE9FE),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFC4B5FD)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.link_rounded,
                                      color: Color(0xFF6A1B9A), size: 16),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Link de pagamento gerado:',
                                    style: GoogleFonts.plusJakartaSans(
                                      color: const Color(0xFF4A1C6A),
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              InkWell(
                                onTap: () {
                                  final link = widget.linkPagamento;
                                  if (link != null && link.isNotEmpty) {
                                    Clipboard.setData(ClipboardData(text: link));
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                          content: const Text('Link copiado para a área de transferência!'),
                                          duration: const Duration(seconds: 2),
                                          behavior: SnackBarBehavior.floating,
                                        ),
                                      );
                                    }
                                  }
                                },
                                child: Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    widget.linkPagamento!,
                                    style: GoogleFonts.plusJakartaSans(
                                      color: const Color(0xFF6A1B9A),
                                      fontSize: 11,
                                      decoration: TextDecoration.underline,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  const Icon(Icons.info_outline_rounded,
                                      color: Color(0xFF6A1B9A), size: 12),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Clique para copiar o link',
                                    style: GoogleFonts.plusJakartaSans(
                                      color: const Color(0xFF64748B),
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],

                      const SizedBox(height: 20),

                      // Botão Fechar
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: corPrimaria,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          onPressed: () => Navigator.of(context).pop(),
                          child: Text(
                            isSuccess ? 'Fechar' : 'Tentar novamente',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ],
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
