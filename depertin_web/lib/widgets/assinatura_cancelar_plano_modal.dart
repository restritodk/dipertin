import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../constants/assinatura_cancelamento_motivos.dart';
import '../models/cliente_assinatura_model.dart';

const Color _textoPrimario = Color(0xFF17152A);
const Color _textoSecundario = Color(0xFF6E7894);
const Color _bordaCard = Color(0xFFEEEAF6);
const Color _bordaInput = Color(0xFFE9E8F0);
const Color _roxoCard = Color(0xFF6E22D9);
const Color _vermelhoStatus = Color(0xFFF04438);
const Color _vermelhoFundo = Color(0xFFFEF2F2);
const Color _laranjaStatus = Color(0xFFFF7A17);
const Color _laranjaFundo = Color(0xFFFFF3E6);

/// Modal premium para cancelamento de plano pelo admin.
///
/// Retorna [AssinaturaCancelamentoResultado] se confirmado, `null` se cancelado.
Future<AssinaturaCancelamentoResultado?> mostrarAssinaturaCancelarPlanoModal(
  BuildContext context, {
  required ClienteAssinaturaModel cliente,
}) {
  return showDialog<AssinaturaCancelamentoResultado>(
    context: context,
    useRootNavigator: true,
    barrierDismissible: false,
    barrierColor: Colors.black.withValues(alpha: 0.55),
    builder: (_) => _AssinaturaCancelarPlanoModal(cliente: cliente),
  );
}

class AssinaturaCancelamentoResultado {
  const AssinaturaCancelamentoResultado({
    required this.motivoCodigo,
    this.motivoOutroTexto,
    this.observacaoInterna,
  });

  final String motivoCodigo;
  final String? motivoOutroTexto;
  final String? observacaoInterna;
}

class _AssinaturaCancelarPlanoModal extends StatefulWidget {
  const _AssinaturaCancelarPlanoModal({required this.cliente});

  final ClienteAssinaturaModel cliente;

  @override
  State<_AssinaturaCancelarPlanoModal> createState() =>
      _AssinaturaCancelarPlanoModalState();
}

class _AssinaturaCancelarPlanoModalState
    extends State<_AssinaturaCancelarPlanoModal> {
  String? _motivoCodigo;
  final _motivoOutroCtl = TextEditingController();
  final _obsInternaCtl = TextEditingController();
  String? _erroMotivo;
  String? _erroOutro;

  @override
  void dispose() {
    _motivoOutroCtl.dispose();
    _obsInternaCtl.dispose();
    super.dispose();
  }

  bool get _precisaOutro =>
      _motivoCodigo == AssinaturaCancelamentoMotivo.codigoOutro;

  String get _valorMensalExibir {
    return NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$')
        .format(widget.cliente.monthlyAmount);
  }

  bool _validar() {
    setState(() {
      _erroMotivo = null;
      _erroOutro = null;
    });

    if (_motivoCodigo == null || _motivoCodigo!.isEmpty) {
      setState(() => _erroMotivo = 'Selecione um motivo para continuar.');
      return false;
    }

    if (_precisaOutro) {
      final t = _motivoOutroCtl.text.trim();
      if (t.length < 3) {
        setState(
          () => _erroOutro = 'Descreva o motivo (mínimo 3 caracteres).',
        );
        return false;
      }
    }

    return true;
  }

  void _confirmar() {
    if (!_validar()) return;

    Navigator.of(context).pop(
      AssinaturaCancelamentoResultado(
        motivoCodigo: _motivoCodigo!,
        motivoOutroTexto:
            _precisaOutro ? _motivoOutroCtl.text.trim() : null,
        observacaoInterna: _obsInternaCtl.text.trim().isEmpty
            ? null
            : _obsInternaCtl.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cliente = widget.cliente;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 720),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Flexible(
              child: SingleChildScrollView(
                primary: false,
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: _vermelhoFundo,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Icon(
                        Icons.cancel_outlined,
                        size: 28,
                        color: _vermelhoStatus,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Cancelar plano',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: _textoPrimario,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Revise as informações da assinatura antes de confirmar o cancelamento.',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 14,
                        color: _textoSecundario,
                        height: 1.45,
                      ),
                    ),
                    const SizedBox(height: 20),
                    _InfoCard(
                      children: [
                        _InfoRow(
                          label: 'Nome da loja',
                          value: cliente.storeName,
                        ),
                        _InfoRow(label: 'E-mail', value: cliente.email),
                        _InfoRow(
                          label: 'Plano contratado',
                          value: cliente.planName,
                          destaque: true,
                        ),
                        _InfoRow(
                          label: 'Valor mensal',
                          value: _valorMensalExibir,
                        ),
                        _InfoRow(
                          label: 'Data da contratação',
                          value: cliente.createdAtExibir,
                        ),
                        _InfoRow(
                          label: 'Próxima cobrança',
                          value: cliente.nextBillingDateExibir,
                        ),
                        _InfoRow(
                          label: 'Status atual',
                          value: cliente.statusRotulo,
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Motivo do cancelamento *',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: _textoPrimario,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ...AssinaturaCancelamentoMotivo.opcoes.map(
                      (m) => _MotivoTile(
                        rotulo: m.rotulo,
                        selecionado: _motivoCodigo == m.codigo,
                        onTap: () => setState(() {
                          _motivoCodigo = m.codigo;
                          _erroMotivo = null;
                          _erroOutro = null;
                        }),
                      ),
                    ),
                    if (_erroMotivo != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        _erroMotivo!,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 12,
                          color: _vermelhoStatus,
                        ),
                      ),
                    ],
                    if (_precisaOutro) ...[
                      const SizedBox(height: 12),
                      TextField(
                        controller: _motivoOutroCtl,
                        maxLines: 3,
                        maxLength: 500,
                        onChanged: (_) {
                          if (_erroOutro != null) {
                            setState(() => _erroOutro = null);
                          }
                        },
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 13,
                          color: _textoPrimario,
                        ),
                        decoration: InputDecoration(
                          hintText: 'Descreva o motivo do cancelamento…',
                          hintStyle: GoogleFonts.plusJakartaSans(
                            fontSize: 13,
                            color: _textoSecundario,
                          ),
                          filled: true,
                          fillColor: Colors.white,
                          counterStyle: GoogleFonts.plusJakartaSans(
                            fontSize: 11,
                            color: _textoSecundario,
                          ),
                          contentPadding: const EdgeInsets.all(12),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(
                              color: _erroOutro != null
                                  ? _vermelhoStatus
                                  : _bordaInput,
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(
                              color: _erroOutro != null
                                  ? _vermelhoStatus
                                  : _bordaInput,
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(
                              color: _erroOutro != null
                                  ? _vermelhoStatus
                                  : _roxoCard,
                              width: 1.5,
                            ),
                          ),
                        ),
                      ),
                      if (_erroOutro != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            _erroOutro!,
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 12,
                              color: _vermelhoStatus,
                            ),
                          ),
                        ),
                    ],
                    const SizedBox(height: 16),
                    Text(
                      'Observação interna (opcional)',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: _textoPrimario,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Visível apenas para a equipe administrativa.',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 12,
                        color: _textoSecundario,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _obsInternaCtl,
                      maxLines: 2,
                      maxLength: 900,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 13,
                        color: _textoPrimario,
                      ),
                      decoration: InputDecoration(
                        hintText: 'Anotações internas…',
                        hintStyle: GoogleFonts.plusJakartaSans(
                          fontSize: 13,
                          color: _textoSecundario,
                        ),
                        filled: true,
                        fillColor: Colors.white,
                        contentPadding: const EdgeInsets.all(12),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(color: _bordaInput),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(color: _bordaInput),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(
                            color: _roxoCard,
                            width: 1.5,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: _laranjaFundo,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: _laranjaStatus.withValues(alpha: 0.35),
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            Icons.warning_amber_rounded,
                            size: 20,
                            color: _laranjaStatus,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Ao cancelar este plano, o lojista perderá acesso ao Gestão Comercial e será redirecionado para a tela de contratação.',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 13,
                                color: const Color(0xFF92400E),
                                height: 1.45,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: _bordaCard)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Color(0xFFD4C8F0)),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      backgroundColor: Colors.white,
                    ),
                    child: Text(
                      'Voltar',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: _textoSecundario,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  FilledButton(
                    onPressed: _confirmar,
                    style: FilledButton.styleFrom(
                      backgroundColor: _vermelhoStatus,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: Text(
                      'Confirmar cancelamento',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
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
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFCFCFE),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _bordaCard),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Informações do lojista',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: _roxoCard,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.label,
    required this.value,
    this.destaque = false,
  });

  final String label;
  final String value;
  final bool destaque;

  @override
  Widget build(BuildContext context) {
    final exibir = value.trim().isEmpty ? '—' : value.trim();
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 12,
                color: _textoSecundario,
              ),
            ),
          ),
          Expanded(
            child: Text(
              exibir,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13,
                fontWeight: destaque ? FontWeight.w700 : FontWeight.w500,
                color: destaque ? _roxoCard : _textoPrimario,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MotivoTile extends StatelessWidget {
  const _MotivoTile({
    required this.rotulo,
    required this.selecionado,
    required this.onTap,
  });

  final String rotulo;
  final bool selecionado;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
          child: Row(
            children: [
              Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: selecionado ? _roxoCard : _bordaInput,
                    width: selecionado ? 6 : 2,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  rotulo,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 13,
                    color: _textoPrimario,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
