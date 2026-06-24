import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/painel_admin_theme.dart';
import '../utils/admin_perfil.dart';
class BannersScreen extends StatefulWidget {
  const BannersScreen({super.key});

  @override
  State<BannersScreen> createState() => _BannersScreenState();
}

class _BannersScreenState extends State<BannersScreen> {
  final _filtroBuscaCtrl = TextEditingController();
  String _filtroStatus = '';
  bool _modoGrid = true;

  @override
  void dispose() {
    _filtroBuscaCtrl.dispose();
    super.dispose();
  }

  // ===== HELPERS DE STATUS =====
  String _statusBanner(Map<String, dynamic> dados) {
    final ativo = dados['ativo'] != false;
    if (!ativo) return 'pausado';
    final dataFim = (dados['data_fim'] as Timestamp?)?.toDate();
    if (dataFim == null) return 'ativo';
    if (dataFim.isBefore(DateTime.now())) return 'expirado';
    if (dataFim.difference(DateTime.now()).inDays <= 3) return 'vencendo';
    return 'ativo';
  }

  int _diasRestantes(Map<String, dynamic> dados) {
    final dataFim = (dados['data_fim'] as Timestamp?)?.toDate();
    if (dataFim == null) return 0;
    return dataFim.difference(DateTime.now()).inDays.clamp(0, 9999);
  }

  String _formatarDataBanner(dynamic data) {
    if (data is Timestamp) {
      final dt = data.toDate();
      return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
    }
    return '—';
  }

  Color _corStatus(String status) {
    switch (status) {
      case 'ativo': return const Color(0xFF22C55E);
      case 'vencendo': return const Color(0xFFF59E0B);
      case 'pausado': return const Color(0xFF94A3B8);
      case 'expirado': return const Color(0xFFEF4444);
      default: return const Color(0xFF94A3B8);
    }
  }

  String _rotuloStatus(String status) {
    switch (status) {
      case 'ativo': return 'Ativo';
      case 'vencendo': return 'Vencendo';
      case 'pausado': return 'Pausado';
      case 'expirado': return 'Expirado';
      default: return status;
    }
  }

  IconData _iconeStatus(String status) {
    switch (status) {
      case 'ativo': return Icons.check_circle_rounded;
      case 'vencendo': return Icons.schedule_rounded;
      case 'pausado': return Icons.pause_circle_rounded;
      case 'expirado': return Icons.timer_off_rounded;
      default: return Icons.circle_rounded;
    }
  }

  double _calcularProgresso(Map<String, dynamic> dados) {
    final dtInicio = (dados['data_inicio'] as Timestamp?)?.toDate();
    final dtFim = (dados['data_fim'] as Timestamp?)?.toDate();
    if (dtInicio == null || dtFim == null || dtFim.isBefore(dtInicio)) return 1.0;
    final agora = DateTime.now();
    if (agora.isBefore(dtInicio)) return 0.0;
    if (agora.isAfter(dtFim)) return 1.0;
    final total = dtFim.difference(dtInicio).inMilliseconds.toDouble();
    final decorrido = agora.difference(dtInicio).inMilliseconds.toDouble();
    return (decorrido / total).clamp(0.0, 1.0);
  }

  void _mostrarModalBanner({
    String? bannerId,
    Map<String, dynamic>? dadosAtuais,
  }) {
    final isEditando = bannerId != null;
    Uint8List? novaImagemBytes;
    String? imagemAtualUrl =
        dadosAtuais != null ? dadosAtuais['url_imagem'] as String? : null;

    final linkC = TextEditingController(
      text: dadosAtuais != null ? dadosAtuais['link_destino'] ?? '' : '',
    );
    final cidadeC = TextEditingController(
      text: dadosAtuais != null ? dadosAtuais['cidade'] ?? 'Todas' : 'Todas',
    );
    final valorC = TextEditingController(
      text: dadosAtuais != null
          ? (dadosAtuais['valor']?.toString() ?? '0')
          : '0',
    );

    String tipoCobranca = dadosAtuais != null
        ? (dadosAtuais['tipo_cobranca'] ?? 'dia').toString()
        : 'dia';

    DateTime dataInicio = dadosAtuais != null &&
            dadosAtuais['data_inicio'] != null
        ? (dadosAtuais['data_inicio'] as Timestamp).toDate()
        : DateTime.now();

    DateTime dataFim = dadosAtuais != null && dadosAtuais['data_fim'] != null
        ? (dadosAtuais['data_fim'] as Timestamp).toDate()
        : DateTime.now().add(const Duration(days: 7));

    bool isLoading = false;

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.45),
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setState) {
            Future<void> escolherImagem() async {
              final result = await FilePicker.platform.pickFiles(
                type: FileType.image,
              );
              if (result != null && result.files.first.bytes != null) {
                setState(() => novaImagemBytes = result.files.first.bytes);
              }
            }

            Future<void> escolherData(bool isInicio) async {
              final selecionada = await showDatePicker(
                context: context,
                initialDate: isInicio ? dataInicio : dataFim,
                firstDate: DateTime(2024),
                lastDate: DateTime(2035),
              );
              if (selecionada != null) {
                setState(() {
                  if (isInicio) {
                    dataInicio = selecionada;
                  } else {
                    dataFim = selecionada;
                  }
                });
              }
            }

            Future<void> salvarBanner() async {
              if (!isEditando && novaImagemBytes == null) {
                mostrarSnackPainel(context,
                    erro: true,
                    mensagem: 'Escolha uma imagem para o novo banner.');
                return;
              }

              setState(() => isLoading = true);

              try {
                var urlDownload = imagemAtualUrl ?? '';

                if (novaImagemBytes != null) {
                  final nomeArquivo =
                      'banner_${DateTime.now().millisecondsSinceEpoch}.jpg';
                  final ref = FirebaseStorage.instance
                      .ref()
                      .child('banners_vitrine/$nomeArquivo');
                  await ref.putData(
                    novaImagemBytes!,
                    SettableMetadata(contentType: 'image/jpeg'),
                  );
                  urlDownload = await ref.getDownloadURL();
                }

                final valorConvertido =
                    double.tryParse(valorC.text.replaceAll(',', '.')) ?? 0.0;

                int diasBanner = dataFim.difference(dataInicio).inDays + 1;
                if (diasBanner < 1) diasBanner = 1;
                double valorTotalBanner = 0;
                if (valorConvertido > 0) {
                  switch (tipoCobranca) {
                    case 'fixo':
                      valorTotalBanner = valorConvertido;
                      break;
                    case 'mensal':
                      final meses = (diasBanner / 30).ceil().clamp(1, 9999);
                      valorTotalBanner = valorConvertido * meses;
                      break;
                    case 'hora':
                      valorTotalBanner = valorConvertido * diasBanner * 24;
                      break;
                    case 'dia':
                    default:
                      valorTotalBanner = valorConvertido * diasBanner;
                      break;
                  }
                }

                final dadosSalvar = <String, dynamic>{
                  'url_imagem': urlDownload,
                  'link_destino': linkC.text.trim(),
                  'cidade': cidadeC.text.trim().toLowerCase(),
                  'valor': valorConvertido,
                  'tipo_cobranca': tipoCobranca,
                  'data_inicio': Timestamp.fromDate(dataInicio),
                  'data_fim': Timestamp.fromDate(dataFim),
                  'valor_total': valorTotalBanner,
                  'ativo': true,
                  'data_atualizacao': FieldValue.serverTimestamp(),
                };

                if (isEditando) {
                  await FirebaseFirestore.instance
                      .collection('banners')
                      .doc(bannerId)
                      .update(dadosSalvar);
                  // Sincroniza receita no Livro Caixa / Relatório Financeiro
                  if (valorTotalBanner > 0) {
                    await _sincronizarReceitaBanner(
                      bannerId: bannerId,
                      valorConvertido: valorConvertido,
                      valorTotal: valorTotalBanner,
                      tipoCobranca: tipoCobranca,
                      dataInicio: dataInicio,
                      dataFim: dataFim,
                      dias: diasBanner,
                      cidade: cidadeC.text.trim().toLowerCase(),
                    );
                  }
                } else {
                  dadosSalvar['data_criacao'] = FieldValue.serverTimestamp();
                  final docRef = await FirebaseFirestore.instance
                      .collection('banners')
                      .add(dadosSalvar);
                  // Sincroniza receita no Livro Caixa / Relatório Financeiro
                  if (valorTotalBanner > 0) {
                    await _sincronizarReceitaBanner(
                      bannerId: docRef.id,
                      valorConvertido: valorConvertido,
                      valorTotal: valorTotalBanner,
                      tipoCobranca: tipoCobranca,
                      dataInicio: dataInicio,
                      dataFim: dataFim,
                      dias: diasBanner,
                      cidade: cidadeC.text.trim().toLowerCase(),
                    );
                  }
                }

                if (context.mounted) {
                  Navigator.pop(context);
                  mostrarSnackPainel(context,
                      mensagem:
                          isEditando ? 'Banner atualizado!' : 'Banner publicado!');
                }
              } catch (e) {
                if (context.mounted) {
                  mostrarSnackPainel(context,
                      erro: true, mensagem: 'Erro: $e');
                }
              } finally {
                setState(() => isLoading = false);
              }
            }

            String formatarData(DateTime data) =>
                '${data.day.toString().padLeft(2, '0')}/${data.month.toString().padLeft(2, '0')}/${data.year}';

            InputDecoration fieldDeco(String label, {String? hint}) {
              return InputDecoration(
                labelText: label,
                hintText: hint,
                labelStyle: GoogleFonts.plusJakartaSans(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                  color: PainelAdminTheme.textoSecundario,
                ),
                floatingLabelStyle: GoogleFonts.plusJakartaSans(
                  fontWeight: FontWeight.w700,
                  color: PainelAdminTheme.roxo,
                ),
                filled: true,
                fillColor: const Color(0xFFF8FAFC),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide:
                      const BorderSide(color: PainelAdminTheme.roxo, width: 1.6),
                ),
              );
            }

            Widget secaoTitulo(String t) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 10, top: 4),
                child: Text(
                  t,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.1,
                    color: PainelAdminTheme.textoSecundario,
                  ),
                ),
              );
            }

            final maxDialogH = MediaQuery.sizeOf(context).height * 0.92;
            return Dialog(
              backgroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: 520, maxHeight: maxDialogH),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(22, 20, 8, 12),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: PainelAdminTheme.roxo.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color:
                                    PainelAdminTheme.roxo.withValues(alpha: 0.15),
                              ),
                            ),
                            child: Icon(
                              isEditando
                                  ? Icons.edit_outlined
                                  : Icons.add_photo_alternate_outlined,
                              color: PainelAdminTheme.roxo,
                              size: 26,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  isEditando
                                      ? 'Editar banner'
                                      : 'Novo banner promocional',
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: -0.3,
                                    color: PainelAdminTheme.dashboardInk,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Preencha os dados para exibir na vitrine do app.',
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 13,
                                    height: 1.35,
                                    color: PainelAdminTheme.textoSecundario,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: 'Fechar',
                            onPressed: () => Navigator.pop(context),
                            icon: Icon(
                              Icons.close_rounded,
                              color: PainelAdminTheme.textoSecundario,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1, color: Color(0xFFE2E8F0)),
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            secaoTitulo('IMAGEM DO BANNER'),
                            Material(
                              color: Colors.transparent,
                              child: InkWell(
                                onTap: escolherImagem,
                                borderRadius: BorderRadius.circular(16),
                                child: Container(
                                  height: 168,
                                  width: double.infinity,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF8FAFC),
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(
                                      color: const Color(0xFFE2E8F0),
                                    ),
                                  ),
                                  child: novaImagemBytes != null
                                      ? ClipRRect(
                                          borderRadius:
                                              BorderRadius.circular(15),
                                          child: Image.memory(
                                            novaImagemBytes!,
                                            fit: BoxFit.cover,
                                            width: double.infinity,
                                            height: 168,
                                          ),
                                        )
                                      : imagemAtualUrl != null &&
                                              imagemAtualUrl.isNotEmpty
                                          ? ClipRRect(
                                              borderRadius:
                                                  BorderRadius.circular(15),
                                              child: Image.network(
                                                imagemAtualUrl,
                                                fit: BoxFit.cover,
                                                width: double.infinity,
                                                height: 168,
                                                errorBuilder: (_, _, _) =>
                                                    _bannerImageErrorPlaceholder(),
                                              ),
                                            )
                                          : _uploadPlaceholder(),
                                ),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Text(
                                'Formatos JPG ou PNG · recomendado largura ≥ 1200px · máx. ~15 MB no Storage',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 11.5,
                                  height: 1.35,
                                  color: PainelAdminTheme.textoSecundario,
                                ),
                              ),
                            ),
                            const SizedBox(height: 18),
                            secaoTitulo('LOCAL E DESTINO'),
                            TextField(
                              controller: cidadeC,
                              style: GoogleFonts.plusJakartaSans(fontSize: 14),
                              decoration: fieldDeco(
                                'Cidade',
                                hint: 'todas, rondonópolis, toledo…',
                              ),
                            ),
                            const SizedBox(height: 14),
                            TextField(
                              controller: linkC,
                              style: GoogleFonts.plusJakartaSans(fontSize: 14),
                              decoration: fieldDeco(
                                'Link ou ID da loja destino',
                                hint: 'URL ou ID do documento da loja',
                              ),
                            ),
                            const SizedBox(height: 18),
                            secaoTitulo('PERÍODO DE VEICULAÇÃO'),
                            LayoutBuilder(
                              builder: (ctx, c) {
                                final narrow = c.maxWidth < 420;
                                if (narrow) {
                                  return Column(
                                    children: [
                                      _dataChip(
                                        label: 'Início',
                                        data: formatarData(dataInicio),
                                        icon: Icons.calendar_today_outlined,
                                        onTap: () => escolherData(true),
                                      ),
                                      const SizedBox(height: 10),
                                      _dataChip(
                                        label: 'Fim',
                                        data: formatarData(dataFim),
                                        icon: Icons.event_outlined,
                                        onTap: () => escolherData(false),
                                      ),
                                    ],
                                  );
                                }
                                return Row(
                                  children: [
                                    Expanded(
                                      child: _dataChip(
                                        label: 'Início',
                                        data: formatarData(dataInicio),
                                        icon: Icons.calendar_today_outlined,
                                        onTap: () => escolherData(true),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: _dataChip(
                                        label: 'Fim',
                                        data: formatarData(dataFim),
                                        icon: Icons.event_outlined,
                                        onTap: () => escolherData(false),
                                      ),
                                    ),
                                  ],
                                );
                              },
                            ),
                            const SizedBox(height: 18),
                            secaoTitulo('PRECIFICAÇÃO (REFERÊNCIA)'),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  flex: 5,
                                  child: DropdownButtonFormField<String>(
                                    // Controlled: [value] mantém seleção ao setState.
                                    // ignore: deprecated_member_use
                                    value: tipoCobranca,
                                    decoration: fieldDeco('Cobrar por'),
                                    dropdownColor: Colors.white,
                                    borderRadius: BorderRadius.circular(12),
                                    items: [
                                      DropdownMenuItem(
                                        value: 'dia',
                                        child: Text(
                                          'Por dia',
                                          style: GoogleFonts.plusJakartaSans(
                                              fontSize: 14),
                                        ),
                                      ),
                                      DropdownMenuItem(
                                        value: 'hora',
                                        child: Text(
                                          'Por hora',
                                          style: GoogleFonts.plusJakartaSans(
                                              fontSize: 14),
                                        ),
                                      ),
                                      DropdownMenuItem(
                                        value: 'fixo',
                                        child: Text(
                                          'Valor fixo',
                                          style: GoogleFonts.plusJakartaSans(
                                              fontSize: 14),
                                        ),
                                      ),
                                    ],
                                    onChanged: (val) {
                                      if (val != null) {
                                        setState(() => tipoCobranca = val);
                                      }
                                    },
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  flex: 5,
                                  child: TextField(
                                    controller: valorC,
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                            decimal: true),
                                    style:
                                        GoogleFonts.plusJakartaSans(fontSize: 14),
                                    decoration: fieldDeco(
                                      'Valor',
                                      hint: 'ex.: 14,50',
                                    ).copyWith(
                                      prefixText: 'R\$ ',
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    const Divider(height: 1, color: Color(0xFFE2E8F0)),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
                      child: Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed:
                                  isLoading ? null : () => Navigator.pop(context),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: PainelAdminTheme.roxo,
                                side: BorderSide(
                                  color: PainelAdminTheme.roxo
                                      .withValues(alpha: 0.35),
                                ),
                                padding:
                                    const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: Text(
                                'Cancelar',
                                style: GoogleFonts.plusJakartaSans(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 2,
                            child: FilledButton.icon(
                              onPressed: isLoading ? null : salvarBanner,
                              icon: isLoading
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : Icon(
                                      isEditando
                                          ? Icons.save_outlined
                                          : Icons.publish_rounded,
                                      size: 20,
                                    ),
                              label: Text(
                                isLoading
                                    ? 'Salvando…'
                                    : (isEditando
                                        ? 'Salvar alterações'
                                        : 'Publicar banner'),
                                style: GoogleFonts.plusJakartaSans(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                ),
                              ),
                              style: FilledButton.styleFrom(
                                backgroundColor: PainelAdminTheme.roxo,
                                foregroundColor: Colors.white,
                                disabledBackgroundColor:
                                    PainelAdminTheme.roxo.withValues(alpha: 0.45),
                                padding:
                                    const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
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
            );
          },
        );
      },
    );
  }

  /// Espelha o banner no Livro Caixa / Relatório Financeiro (receitas_app),
  /// mesmo padrão de _sincronizarReceitaUtilidade em utilidades_screen.dart.
  Future<void> _sincronizarReceitaBanner({
    required String bannerId,
    required double valorConvertido,
    required double valorTotal,
    required String tipoCobranca,
    required DateTime dataInicio,
    required DateTime dataFim,
    required int dias,
    required String cidade,
  }) async {
    final rid = 'util_banners_${bannerId.replaceAll('/', '_')}';
    await FirebaseFirestore.instance.collection('receitas_app').doc(rid).set({
      'tipo_receita': 'Banners',
      'titulo_referencia': 'Banner ${cidade.isEmpty ? 'Todas' : cidade.toUpperCase()}',
      'nome_pagador': cidade.isEmpty ? 'Anunciante' : cidade,
      'valor_total': valorTotal,
      'valor_unitario': valorConvertido,
      'modalidade_valor': tipoCobranca,
      'data_inicio': Timestamp.fromDate(dataInicio),
      'data_fim': Timestamp.fromDate(dataFim),
      'qtd_dias': dias,
      'utilidade_colecao': 'banners',
      'utilidade_anuncio_id': bannerId,
      'livro_caixa_manual': false,
      'data_registro': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Widget _uploadPlaceholder() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          Icons.add_photo_alternate_outlined,
          size: 40,
          color: PainelAdminTheme.textoSecundario.withValues(alpha: 0.85),
        ),
        const SizedBox(height: 10),
        Text(
          'Clique ou toque para escolher a imagem',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: PainelAdminTheme.dashboardInk,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Ideal: banner horizontal (ex. 3:1 ou 16:9)',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 12,
            color: PainelAdminTheme.textoSecundario,
          ),
        ),
      ],
    );
  }

  Widget _bannerImageErrorPlaceholder() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.broken_image_outlined,
            size: 36,
            color: PainelAdminTheme.textoSecundario,
          ),
          const SizedBox(height: 8),
          Text(
            'Não foi possível carregar a imagem',
            textAlign: TextAlign.center,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 12,
              color: PainelAdminTheme.textoSecundario,
            ),
          ),
        ],
      ),
    );
  }

  Widget _dataChip({
    required String label,
    required String data,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Row(
            children: [
              Icon(icon, size: 20, color: PainelAdminTheme.roxo),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: PainelAdminTheme.textoSecundario,
                      ),
                    ),
                    Text(
                      data,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: PainelAdminTheme.dashboardInk,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.edit_calendar_outlined,
                size: 18,
                color: PainelAdminTheme.textoSecundario,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _deletarBanner(String id, String urlImagem) async {
    final ok = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.45),
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEF2F2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.delete_outline_rounded,
                          color: Color(0xFFDC2626), size: 24),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        'Remover banner',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: PainelAdminTheme.dashboardInk,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  'O banner sai do ar imediatamente. A imagem será apagada do armazenamento.',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 14,
                    height: 1.45,
                    color: PainelAdminTheme.textoSecundario,
                  ),
                ),
                const SizedBox(height: 22),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: PainelAdminTheme.roxo,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: Text(
                          'Cancelar',
                          style: GoogleFonts.plusJakartaSans(
                              fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFFDC2626),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: Text(
                          'Apagar',
                          style: GoogleFonts.plusJakartaSans(
                              fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await FirebaseFirestore.instance.collection('banners').doc(id).delete();
      await FirebaseStorage.instance.refFromURL(urlImagem).delete();
      if (mounted) {
        mostrarSnackPainel(context, mensagem: 'Banner removido.');
      }
    } catch (e) {
      debugPrint('Erro ao apagar: $e');
      if (mounted) {
        mostrarSnackPainel(context,
            erro: true, mensagem: 'Não foi possível apagar: $e');
      }
    }
  }

  String _rotuloTipoCobranca(String? t) {
    switch (t) {
      case 'hora':
        return 'hora';
      case 'fixo':
        return 'fixo';
      case 'dia':
      default:
        return 'dia';
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenW = MediaQuery.sizeOf(context).width;
    final isCompact = screenW < 640;

    return Scaffold(
      backgroundColor: const Color(0xFFF8F7FC),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('banners')
            .orderBy('data_criacao', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          final isLoading = snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData;
          final banners = snapshot.data?.docs ?? [];
          final total = banners.length;

          // Métricas
          final agora = DateTime.now();
          int ativos = 0, vencendo = 0;
          double receitaMes = 0;

          for (final doc in banners) {
            final d = doc.data()! as Map<String, dynamic>;
            final ativo = d['ativo'] != false;
            final dataFim = (d['data_fim'] as Timestamp?)?.toDate();
            final dataInicio = (d['data_inicio'] as Timestamp?)?.toDate();
            final valorTotal = (d['valor_total'] as num?)?.toDouble() ?? 0;
            if (ativo && dataFim != null && !dataFim.isBefore(agora)) {
              ativos++;
              if (dataFim.difference(agora).inDays <= 3) vencendo++;
            }
            if (dataInicio != null && dataFim != null) {
              final mesAtual = DateTime(agora.year, agora.month, 1);
              final proxMes = DateTime(agora.year, agora.month + 1, 1);
              if (!dataFim.isBefore(mesAtual) && dataInicio.isBefore(proxMes)) {
                final diasMes = proxMes.difference(mesAtual).inDays;
                final diasBanner = dataFim.difference(dataInicio).inDays + 1;
                if (diasBanner > 0) receitaMes += (valorTotal / diasBanner) * diasMes;
              }
            }
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ===== HEADER com Breadcrumb =====
              Container(
                color: Colors.white,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(32, 24, 32, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Text('Marketing',
                              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF6A1B9A))),
                          const SizedBox(width: 6),
                          const Text('/', style: TextStyle(fontSize: 13, color: Color(0xFFCBD5E1))),
                          const SizedBox(width: 6),
                          const Text('Banners da vitrine',
                              style: TextStyle(fontSize: 13, color: Color(0xFF64748B))),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Vitrine Publicitária',
                                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: Color(0xFF1A1A2E), letterSpacing: -0.3),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'Gerencie os banners exibidos no app, valores, períodos e destinos.',
                                  style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          // Resumo card
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF3EFF7),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: const Color(0xFF6A1B9A).withValues(alpha: 0.12)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 38, height: 38,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF6A1B9A).withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: const Icon(Icons.view_carousel_rounded, color: Color(0xFF6A1B9A), size: 20),
                                ),
                                const SizedBox(width: 10),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      '$total banners',
                                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Color(0xFF1A1A2E)),
                                    ),
                                    const SizedBox(height: 1),
                                    Text(
                                      '$ativos ativos',
                                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          if (!isCompact)
                            SizedBox(
                              height: 46,
                              child: FilledButton.icon(
                                onPressed: () => _mostrarModalBanner(),
                                icon: const Icon(Icons.add_rounded, size: 20),
                                label: const Text('+ Novo banner', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                                style: FilledButton.styleFrom(
                                  backgroundColor: Color(0xFFFF8F00),
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(horizontal: 22),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 20),
                    ],
                  ),
                ),
              ),
              Divider(height: 1, color: Colors.grey.shade200),

              // ===== CARDS DE RESUMO =====
              Padding(
                padding: const EdgeInsets.fromLTRB(32, 20, 32, 0),
                child: Wrap(
                  spacing: 14,
                  runSpacing: 12,
                  children: [
                    _cardResumo('Banners ativos', '$ativos', Icons.check_circle_rounded, const Color(0xFF22C55E)),
                    _cardResumo('Vencendo em breve', '$vencendo', Icons.schedule_rounded, const Color(0xFFF59E0B)),
                    _cardResumo('Receita do mês', 'R\$ ${receitaMes.toStringAsFixed(0)}', Icons.trending_up_rounded, const Color(0xFF6A1B9A)),
                    _cardResumo('Visualizações est.', '—', Icons.visibility_rounded, const Color(0xFF3B82F6)),
                  ],
                ),
              ),

              // ===== FILTROS =====
              Padding(
                padding: const EdgeInsets.fromLTRB(32, 14, 32, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 44,
                        child: TextField(
                          controller: _filtroBuscaCtrl,
                          onChanged: (_) => setState(() {}),
                          decoration: InputDecoration(
                            hintText: 'Buscar banner…',
                            prefixIcon: const Icon(Icons.search_rounded, size: 20, color: Color(0xFF94A3B8)),
                            filled: true,
                            fillColor: Colors.white,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(color: Colors.grey.shade200),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(color: Colors.grey.shade200),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(color: Color(0xFF6A1B9A), width: 1.5),
                            ),
                            isDense: true,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    _buildFiltroDropdown(),
                    const SizedBox(width: 12),
                    if (isCompact)
                      SizedBox(
                        height: 44,
                        child: FilledButton.icon(
                          onPressed: () => _mostrarModalBanner(),
                          icon: const Icon(Icons.add_rounded, size: 18),
                          label: const Text('Novo', style: TextStyle(fontSize: 13)),
                          style: FilledButton.styleFrom(
                            backgroundColor: Color(0xFFFF8F00),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // ===== BARRA CAMPANHAS PUBLICITÁRIAS =====
              Padding(
                padding: const EdgeInsets.fromLTRB(32, 0, 32, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          const Text('Campanhas publicitárias',
                              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: Color(0xFF1A1A2E))),
                          const SizedBox(width: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: const Color(0xFF6A1B9A).withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text('${_buildListaFiltrada(banners).length}',
                                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF6A1B9A))),
                          ),
                        ],
                      ),
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('Ordenar por:', style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8))),
                        const SizedBox(width: 6),
                        const Text('Mais recentes',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF475569))),
                        Icon(Icons.expand_more_rounded, size: 16, color: Colors.grey[500]),
                        const SizedBox(width: 12),
                        Container(height: 20, width: 1, color: Colors.grey[200]),
                        const SizedBox(width: 12),
                        _iconeToggle(Icons.grid_view_rounded, _modoGrid, () => setState(() => _modoGrid = true)),
                        const SizedBox(width: 4),
                        _iconeToggle(Icons.view_list_rounded, !_modoGrid, () => setState(() => _modoGrid = false)),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // ===== LISTA OU EMPTY =====
              Expanded(
                child: isLoading
                    ? const Center(child: CircularProgressIndicator(strokeWidth: 2.5, color: Color(0xFF6A1B9A)))
                    : banners.isEmpty
                        ? _emptyState()
                        : _modoGrid
                            ? _buildGridBanners(banners)
                            : _buildListaBanners(banners),
              ),
              const SizedBox(height: 20),
            ],
          );
        },
      ),
    );
  }

  Widget _cardResumo(String titulo, String valor, IconData icone, Color cor) {
    return SizedBox(
      width: 240,
      child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.035), blurRadius: 6, offset: const Offset(0, 2))],
      ),
      child: Row(
        children: [
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(
              color: cor.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icone, color: cor, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  valor,
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Colors.grey[800], height: 1.1),
                ),
                const SizedBox(height: 2),
                Text(titulo, style: TextStyle(fontSize: 12, color: Colors.grey[500]), maxLines: 1, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        ],
      ),
      ),
    );
  }

  Widget _buildFiltroDropdown() {
    const statusOpcoes = ['', 'ativo', 'vencendo', 'pausado', 'expirado'];
    const rotulos = ['Status: Todos', 'Ativos', 'Vencendo', 'Pausados', 'Expirados'];
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _filtroStatus,
          isDense: true,
          icon: const Icon(Icons.expand_more_rounded, size: 20, color: Color(0xFF94A3B8)),
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF475569)),
          items: List.generate(statusOpcoes.length, (i) => DropdownMenuItem(
            value: statusOpcoes[i],
            child: Text(rotulos[i], style: TextStyle(
              fontWeight: _filtroStatus == statusOpcoes[i] ? FontWeight.w700 : null,
              color: _filtroStatus == statusOpcoes[i] ? const Color(0xFF6A1B9A) : null,
            )),
          )),
          onChanged: (v) => setState(() => _filtroStatus = v ?? ''),
        ),
      ),
    );
  }

  List<QueryDocumentSnapshot> _buildListaFiltrada(List<QueryDocumentSnapshot> banners) {
    return banners.where((doc) {
      final d = doc.data()! as Map<String, dynamic>;
      final busca = _filtroBuscaCtrl.text.trim().toLowerCase();
      if (busca.isNotEmpty) {
        final cidade = (d['cidade'] ?? '').toString().toLowerCase();
        final link = (d['link_destino'] ?? '').toString().toLowerCase();
        if (!cidade.contains(busca) && !link.contains(busca)) return false;
      }
      if (_filtroStatus.isNotEmpty && _statusBanner(d) != _filtroStatus) return false;
      return true;
    }).toList();
  }

  Widget _iconeToggle(IconData icon, bool ativo, VoidCallback onTap) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 36, height: 36,
          decoration: BoxDecoration(
            color: ativo ? const Color(0xFF6A1B9A).withValues(alpha: 0.08) : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 20,
              color: ativo ? const Color(0xFF6A1B9A) : Colors.grey[400]),
        ),
      ),
    );
  }

  Widget _buildGridBanners(List<QueryDocumentSnapshot> banners) {
    final docs = _buildListaFiltrada(banners);
    if (docs.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_off_rounded, size: 48, color: Colors.grey[300]),
            const SizedBox(height: 8),
            Text('Nenhum banner encontrado.', style: TextStyle(color: Colors.grey[500], fontSize: 14)),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(32, 0, 32, 32),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final crossAxisCount = width > 1100 ? 3 : (width > 700 ? 2 : 1);
          final gap = 20.0;
          final cardWidth = (width - gap * (crossAxisCount - 1)) / crossAxisCount;

          return Wrap(
            spacing: gap,
            runSpacing: gap,
            children: docs.map((doc) => SizedBox(
              width: cardWidth,
              child: _buildBannerCard(doc),
            )).toList(),
          );
        },
      ),
    );
  }

  Widget _buildBannerCard(QueryDocumentSnapshot doc) {
    final d = doc.data()! as Map<String, dynamic>;
    final imageUrl = d['url_imagem'] as String? ?? '';
    final cidadeRaw = d['cidade']?.toString() ?? 'todas';
    final cidade = cidadeRaw.toLowerCase() == 'todas' ? 'Todas as cidades' : cidadeRaw.toUpperCase();
    final valor = (d['valor'] as num?)?.toDouble() ?? 0;
    final tipo = _rotuloTipoCobranca(d['tipo_cobranca']?.toString());
    final status = _statusBanner(d);
    final dias = _diasRestantes(d);
    final dataInicio = _formatarDataBanner(d['data_inicio']);
    final dataFim = _formatarDataBanner(d['data_fim']);
    final ativo = d['ativo'] != false;
    final progresso = _calcularProgresso(d);
    final temDataFim = (d['data_fim'] as Timestamp?)?.toDate() != null;

    // Nome exibição: usa cidade ou nome loja
    final titulo = d['nome']?.toString() ?? cidade;
    final subtipo = d['tipo_cobranca']?.toString() ?? 'dia';

    // Dias totais
    int diasTotais = 0;
    final dtInicio = (d['data_inicio'] as Timestamp?)?.toDate();
    final dtFim = (d['data_fim'] as Timestamp?)?.toDate();
    if (dtInicio != null && dtFim != null) {
      diasTotais = dtFim.difference(dtInicio).inDays + 1;
    }

    // Texto rodapé
    String textoRodape;
    Color corRodape;
    if (status == 'expirado') {
      textoRodape = 'Expirado';
      corRodape = const Color(0xFFEF4444);
    } else if (status == 'pausado') {
      textoRodape = 'Pausado';
      corRodape = const Color(0xFF94A3B8);
    } else if (status == 'vencendo') {
      textoRodape = 'Expira em $dias dia${dias == 1 ? '' : 's'}';
      corRodape = const Color(0xFFF59E0B);
    } else {
      textoRodape = 'Ativo por $dias dia${dias == 1 ? '' : 's'}';
      corRodape = const Color(0xFF22C55E);
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: status == 'expirado'
              ? Colors.red.withValues(alpha: 0.2)
              : status == 'pausado'
                  ? Colors.grey.withValues(alpha: 0.2)
                  : Colors.grey.shade200,
        ),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10, offset: const Offset(0, 2))],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ===== IMAGEM =====
          SizedBox(
            height: 150,
            child: Stack(
              children: [
                    // Imagem
                    Positioned.fill(
                      child: imageUrl.isNotEmpty
                          ? Image.network(
                              imageUrl,
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) => Container(
                                color: const Color(0xFFF1F5F9),
                                alignment: Alignment.center,
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.broken_image_outlined, size: 32, color: Colors.grey[300]),
                                    const SizedBox(height: 4),
                                    Text('Banner sem imagem',
                                        style: TextStyle(fontSize: 11, color: Colors.grey[400])),
                                  ],
                                ),
                              ),
                            )
                          : Container(
                              color: const Color(0xFFF1F5F9),
                              alignment: Alignment.center,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.image_outlined, size: 32, color: Colors.grey[300]),
                                  const SizedBox(height: 4),
                                  Text('Banner sem imagem',
                                      style: TextStyle(fontSize: 11, color: Colors.grey[400])),
                                ],
                              ),
                            ),
                    ),
                    // Badge status canto superior esquerdo
                    Positioned(
                      top: 10, left: 10,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: _corStatus(status).withValues(alpha: 0.90),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(_iconeStatus(status), size: 11, color: Colors.white),
                            const SizedBox(width: 4),
                            Text(_rotuloStatus(status),
                                style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.white)),
                          ],
                        ),
                      ),
                    ),
                    // Menu 3 pontos canto superior direito
                    Positioned(
                      top: 6, right: 6,
                      child: PopupMenuButton<_AcaoBanner>(
                        offset: const Offset(0, 4),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 4,
                        color: Colors.white,
                        onSelected: (acao) {
                          switch (acao) {
                            case _AcaoBanner.editar:
                              _mostrarModalBanner(bannerId: doc.id, dadosAtuais: d);
                            case _AcaoBanner.toggleAtivo:
                              _toggleAtivoBanner(doc.id, !ativo);
                            case _AcaoBanner.deletar:
                              _deletarBanner(doc.id, imageUrl);
                          }
                        },
                        itemBuilder: (_) => [
                          PopupMenuItem(
                            value: _AcaoBanner.editar,
                            child: Row(
                              children: [
                                Container(
                                  width: 28, height: 28,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF6A1B9A).withValues(alpha: 0.08),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Icon(Icons.edit_outlined, size: 15, color: Color(0xFF6A1B9A)),
                                ),
                                const SizedBox(width: 10),
                                const Text('Editar', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                              ],
                            ),
                          ),
                          PopupMenuItem(
                            value: _AcaoBanner.toggleAtivo,
                            child: Row(
                              children: [
                                Container(
                                  width: 28, height: 28,
                                  decoration: BoxDecoration(
                                    color: (ativo ? Colors.red : Colors.green).withValues(alpha: 0.10),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Icon(
                                    ativo ? Icons.pause_rounded : Icons.play_arrow_rounded,
                                    size: 15,
                                    color: ativo ? Colors.red : Colors.green,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Text(
                                  ativo ? 'Pausar' : 'Ativar',
                                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                                      color: ativo ? Colors.red : Colors.green),
                                ),
                              ],
                            ),
                          ),
                          const PopupMenuDivider(),
                          PopupMenuItem(
                            value: _AcaoBanner.deletar,
                            child: Row(
                              children: [
                                Container(
                                  width: 28, height: 28,
                                  decoration: BoxDecoration(
                                    color: Colors.red.withValues(alpha: 0.10),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Icon(Icons.delete_outline_rounded, size: 15, color: Colors.red),
                                ),
                                const SizedBox(width: 10),
                                const Text('Deletar', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.red)),
                              ],
                            ),
                          ),
                        ],
                        child: Container(
                          width: 32, height: 32,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.92),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Center(child: Icon(Icons.more_vert_rounded, size: 16, color: Colors.grey[600])),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // ===== CONTEÚDO =====
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Título
                    Text(
                      titulo,
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF1A1A2E)),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Banner · $subtipo',
                      style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    // Chips
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        _bannerChip(Icons.place_outlined, cidade, const Color(0xFF6A1B9A)),
                        if (valor > 0)
                          _bannerChip(Icons.attach_money_rounded, 'R\$ ${valor.toStringAsFixed(0)}/$tipo',
                              const Color(0xFFFF8F00)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    // Período
                    Row(
                      children: [
                        Icon(Icons.date_range_rounded, size: 12, color: Colors.grey[400]),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text('$dataInicio — $dataFim',
                              style: TextStyle(fontSize: 10, color: Colors.grey[500]),
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    // Barra de progresso
                    if (temDataFim && diasTotais > 1) ...[
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: progresso,
                          minHeight: 4,
                          backgroundColor: Colors.grey.shade100,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            status == 'expirado' ? Colors.red : const Color(0xFF6A1B9A),
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                    ],
                    // Rodapé
                    Row(
                      children: [
                        Icon(
                          status == 'expirado'
                              ? Icons.timer_off_rounded
                              : status == 'pausado'
                                  ? Icons.pause_rounded
                                  : Icons.schedule_rounded,
                          size: 12, color: corRodape,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(textoRodape,
                              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: corRodape),
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    // Botão
                    SizedBox(
                      height: 32,
                      child: OutlinedButton(
                        onPressed: () => _mostrarModalBanner(bannerId: doc.id, dadosAtuais: d),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF6A1B9A),
                          side: BorderSide(color: const Color(0xFF6A1B9A).withValues(alpha: 0.3)),
                          padding: const EdgeInsets.symmetric(vertical: 0, horizontal: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          textStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
                        ),
                        child: const Text('Editar'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
  }

  Widget _bannerChip(IconData icon, String text, Color cor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: cor.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 10, color: cor),
          const SizedBox(width: 3),
          Text(text, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: cor)),
        ],
      ),
    );
  }

  Widget _buildListaBanners(List<QueryDocumentSnapshot> banners) {
    final docs = _buildListaFiltrada(banners);
    if (docs.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_off_rounded, size: 48, color: Colors.grey[300]),
            const SizedBox(height: 8),
            Text('Nenhum banner encontrado.', style: TextStyle(color: Colors.grey[500], fontSize: 14)),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(32, 0, 32, 32),
      itemCount: docs.length,
      itemBuilder: (context, i) {
        final doc = docs[i];
        final d = doc.data()! as Map<String, dynamic>;
        final imageUrl = d['url_imagem'] as String? ?? '';
        final cidadeRaw = d['cidade']?.toString() ?? 'todas';
        final cidade = cidadeRaw.toLowerCase() == 'todas' ? 'Todas as cidades' : cidadeRaw.toUpperCase();
        final valor = (d['valor'] as num?)?.toDouble() ?? 0;
        final tipo = _rotuloTipoCobranca(d['tipo_cobranca']?.toString());
        final status = _statusBanner(d);
        final dias = _diasRestantes(d);
        final ativo = d['ativo'] != false;

        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Container(
            height: 100,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: status == 'expirado'
                    ? Colors.red.withValues(alpha: 0.2)
                    : status == 'pausado'
                        ? Colors.grey.withValues(alpha: 0.2)
                        : Colors.grey.shade200),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 6, offset: const Offset(0, 1))],
            ),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: const BorderRadius.only(topLeft: Radius.circular(14), bottomLeft: Radius.circular(14)),
                  child: SizedBox(
                    width: 100, height: 100,
                    child: imageUrl.isNotEmpty
                        ? Image.network(imageUrl, fit: BoxFit.cover,
                            loadingBuilder: (_, child, progress) => progress == null
                                ? child
                                : Container(color: const Color(0xFFF1F5F9),
                                    child: Center(child: SizedBox(width: 20, height: 20,
                                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.grey[300])))),
                            errorBuilder: (_, _, _) => Container(color: const Color(0xFFF1F5F9),
                              child: Icon(Icons.broken_image_outlined, size: 28, color: Colors.grey[300])))
                        : Container(color: const Color(0xFFF1F5F9),
                            child: Icon(Icons.image_outlined, size: 28, color: Colors.grey[300])),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(cidade, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF1A1A2E)),
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          _bannerChip(Icons.place_outlined, cidade, const Color(0xFF6A1B9A)),
                          const SizedBox(width: 6),
                          if (valor > 0)
                            _bannerChip(Icons.attach_money_rounded, 'R\$ ${valor.toStringAsFixed(0)}/$tipo', const Color(0xFFFF8F00)),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: _corStatus(status).withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: _corStatus(status).withValues(alpha: 0.25)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(_iconeStatus(status), size: 11, color: _corStatus(status)),
                      const SizedBox(width: 3),
                      Text('${_rotuloStatus(status)} · ${dias}d',
                          style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: _corStatus(status))),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                PopupMenuButton<_AcaoBanner>(
                  offset: const Offset(0, 4),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 4, color: Colors.white,
                  onSelected: (acao) {
                    switch (acao) {
                      case _AcaoBanner.editar: _mostrarModalBanner(bannerId: doc.id, dadosAtuais: d);
                      case _AcaoBanner.toggleAtivo: _toggleAtivoBanner(doc.id, !ativo);
                      case _AcaoBanner.deletar: _deletarBanner(doc.id, imageUrl);
                    }
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem(value: _AcaoBanner.editar, child: Row(children: [
                      Container(width: 28, height: 28,
                        decoration: BoxDecoration(color: const Color(0xFF6A1B9A).withValues(alpha: 0.08), borderRadius: BorderRadius.circular(8)),
                        child: const Icon(Icons.edit_outlined, size: 15, color: Color(0xFF6A1B9A))),
                      const SizedBox(width: 10), const Text('Editar', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                    ])),
                    PopupMenuItem(value: _AcaoBanner.toggleAtivo, child: Row(children: [
                      Container(width: 28, height: 28,
                        decoration: BoxDecoration(color: (ativo ? Colors.red : Colors.green).withValues(alpha: 0.10), borderRadius: BorderRadius.circular(8)),
                        child: Icon(ativo ? Icons.pause_rounded : Icons.play_arrow_rounded, size: 15, color: ativo ? Colors.red : Colors.green)),
                      const SizedBox(width: 10),
                      Text(ativo ? 'Pausar' : 'Ativar', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: ativo ? Colors.red : Colors.green)),
                    ])),
                    const PopupMenuDivider(),
                    PopupMenuItem(value: _AcaoBanner.deletar, child: Row(children: [
                      Container(width: 28, height: 28,
                        decoration: BoxDecoration(color: Colors.red.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(8)),
                        child: const Icon(Icons.delete_outline_rounded, size: 15, color: Colors.red)),
                      const SizedBox(width: 10), const Text('Deletar', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.red)),
                    ])),
                  ],
                  child: Container(
                    width: 32, height: 32,
                    decoration: BoxDecoration(
                      color: Colors.white, borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey.shade200)),
                    child: Center(child: Icon(Icons.more_vert_rounded, size: 16, color: Colors.grey[600])),
                  ),
                ),
                const SizedBox(width: 8),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _toggleAtivoBanner(String docId, bool novoAtivo) async {
    await FirebaseFirestore.instance.collection('banners').doc(docId).update({
      'ativo': novoAtivo,
      'data_atualizacao': FieldValue.serverTimestamp(),
    });
    if (mounted) {
      mostrarSnackPainel(context, mensagem: novoAtivo ? 'Banner ativado!' : 'Banner pausado.');
    }
  }

  Widget _emptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 420),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.grey.shade200),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 12, offset: const Offset(0, 4))],
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: const Color(0xFF6A1B9A).withValues(alpha: 0.06),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.view_carousel_outlined, size: 48, color: const Color(0xFF6A1B9A).withValues(alpha: 0.6)),
                ),
                const SizedBox(height: 20),
                const Text(
                  'Nenhum banner cadastrado',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Color(0xFF1A1A2E)),
                ),
                const SizedBox(height: 8),
                Text(
                  'Crie seu primeiro banner para começar a divulgar no app.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, height: 1.4, color: Colors.grey[500]),
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: () => _mostrarModalBanner(),
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('Criar banner', style: TextStyle(fontWeight: FontWeight.w700)),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFFF8F00),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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

enum _AcaoBanner { editar, toggleAtivo, deletar }
