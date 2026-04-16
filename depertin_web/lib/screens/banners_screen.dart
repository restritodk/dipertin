import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/painel_admin_theme.dart';
import '../utils/admin_perfil.dart';
import '../widgets/botao_suporte_flutuante.dart';

class BannersScreen extends StatefulWidget {
  const BannersScreen({super.key});

  @override
  State<BannersScreen> createState() => _BannersScreenState();
}

class _BannersScreenState extends State<BannersScreen> {
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

                final dadosSalvar = <String, dynamic>{
                  'url_imagem': urlDownload,
                  'link_destino': linkC.text.trim(),
                  'cidade': cidadeC.text.trim().toLowerCase(),
                  'valor': valorConvertido,
                  'tipo_cobranca': tipoCobranca,
                  'data_inicio': Timestamp.fromDate(dataInicio),
                  'data_fim': Timestamp.fromDate(dataFim),
                  'ativo': true,
                  'data_atualizacao': FieldValue.serverTimestamp(),
                };

                if (isEditando) {
                  await FirebaseFirestore.instance
                      .collection('banners')
                      .doc(bannerId)
                      .update(dadosSalvar);
                } else {
                  dadosSalvar['data_criacao'] = FieldValue.serverTimestamp();
                  await FirebaseFirestore.instance
                      .collection('banners')
                      .add(dadosSalvar);
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
                                                webHtmlElementStrategy: kIsWeb
                                                    ? WebHtmlElementStrategy
                                                        .prefer
                                                    : WebHtmlElementStrategy
                                                        .never,
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
    final wide = MediaQuery.sizeOf(context).width >= 900;

    return Scaffold(
      backgroundColor: PainelAdminTheme.fundoCanvas,
      floatingActionButton: wide
          ? const BotaoSuporteFlutuante()
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                const BotaoSuporteFlutuante(),
                const SizedBox(height: 14),
                FloatingActionButton.extended(
                  heroTag: 'btn_novo_banner',
                  onPressed: () => _mostrarModalBanner(),
                  backgroundColor: PainelAdminTheme.laranja,
                  foregroundColor: Colors.white,
                  icon: const Icon(Icons.add_photo_alternate_outlined, size: 22),
                  label: Text(
                    'Novo banner',
                    style: GoogleFonts.plusJakartaSans(
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
            ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            width: double.infinity,
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(
                bottom: BorderSide(color: Color(0xFFE2E8F0)),
              ),
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1280),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(28, 26, 28, 22),
                  child: LayoutBuilder(
                    builder: (context, c) {
                      final rowLayout = c.maxWidth >= 640;
                      if (rowLayout) {
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color:
                                    PainelAdminTheme.roxo.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Icon(
                                Icons.view_carousel_rounded,
                                color: PainelAdminTheme.roxo,
                                size: 28,
                              ),
                            ),
                            const SizedBox(width: 18),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Vitrine publicitária',
                                    style: GoogleFonts.plusJakartaSans(
                                      fontSize: 24,
                                      fontWeight: FontWeight.w800,
                                      color: PainelAdminTheme.dashboardInk,
                                      letterSpacing: -0.5,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    'Gerencie os banners exibidos no app. Toque em um card para editar valores, período e destino.',
                                    style: GoogleFonts.plusJakartaSans(
                                      fontSize: 14,
                                      height: 1.45,
                                      color: PainelAdminTheme.textoSecundario,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (wide) ...[
                              StreamBuilder<QuerySnapshot>(
                                stream: FirebaseFirestore.instance
                                    .collection('banners')
                                    .snapshots(),
                                builder: (context, snap) {
                                  final n = snap.data?.docs.length ?? 0;
                                  return Padding(
                                    padding: const EdgeInsets.only(right: 12),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.end,
                                      children: [
                                        Text(
                                          '$n',
                                          style: GoogleFonts.plusJakartaSans(
                                            fontSize: 26,
                                            fontWeight: FontWeight.w800,
                                            color: PainelAdminTheme.roxo,
                                            height: 1,
                                          ),
                                        ),
                                        Text(
                                          n == 1 ? 'banner' : 'banners',
                                          style: GoogleFonts.plusJakartaSans(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                            color: PainelAdminTheme.textoSecundario,
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                              FilledButton.icon(
                                onPressed: () => _mostrarModalBanner(),
                                icon: const Icon(Icons.add_rounded, size: 20),
                                label: Text(
                                  'Novo banner',
                                  style: GoogleFonts.plusJakartaSans(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 14,
                                  ),
                                ),
                                style: FilledButton.styleFrom(
                                  backgroundColor: PainelAdminTheme.laranja,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 20,
                                    vertical: 14,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        );
                      }
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Vitrine publicitária',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              color: PainelAdminTheme.dashboardInk,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Toque em um banner para editar.',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 14,
                              color: PainelAdminTheme.textoSecundario,
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1280),
                child: StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('banners')
                      .orderBy('data_criacao', descending: true)
                      .snapshots(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return Center(
                        child: CircularProgressIndicator(
                          color: PainelAdminTheme.roxo,
                          strokeWidth: 2.5,
                        ),
                      );
                    }
                    if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                      return _emptyState();
                    }

                    final banners = snapshot.data!.docs;

                    return GridView.builder(
                      padding: const EdgeInsets.fromLTRB(24, 24, 24, 100),
                      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: 400,
                        mainAxisSpacing: 20,
                        crossAxisSpacing: 20,
                        childAspectRatio: 16 / 9,
                      ),
                      itemCount: banners.length,
                      itemBuilder: (context, index) {
                        final doc = banners[index];
                        final dados = doc.data()! as Map<String, dynamic>;
                        final imageUrl = dados['url_imagem'] as String? ?? '';
                        final cidadeRaw = dados['cidade']?.toString() ?? 'todas';
                        final cidade = cidadeRaw.toLowerCase() == 'todas'
                            ? 'Todas as cidades'
                            : cidadeRaw.toUpperCase();
                        final valor = dados['valor']?.toString() ?? '0';
                        final tipo = _rotuloTipoCobranca(
                            dados['tipo_cobranca']?.toString());
                        final valorLinha = 'R\$ $valor / $tipo';

                        return Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: () => _mostrarModalBanner(
                              bannerId: doc.id,
                              dadosAtuais: dados,
                            ),
                            borderRadius: BorderRadius.circular(16),
                            child: Container(
                              decoration: PainelAdminTheme.dashboardCard(),
                              clipBehavior: Clip.antiAlias,
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  Image.network(
                                    imageUrl,
                                    fit: BoxFit.cover,
                                    webHtmlElementStrategy: kIsWeb
                                        ? WebHtmlElementStrategy.prefer
                                        : WebHtmlElementStrategy.never,
                                    errorBuilder: (_, _, _) => Container(
                                      color: const Color(0xFFF1F5F9),
                                      alignment: Alignment.center,
                                      child: Icon(
                                        Icons.broken_image_outlined,
                                        size: 48,
                                        color: PainelAdminTheme.textoSecundario,
                                      ),
                                    ),
                                  ),
                                  Positioned(
                                    left: 0,
                                    right: 0,
                                    bottom: 0,
                                    child: Container(
                                      padding: const EdgeInsets.fromLTRB(
                                          12, 32, 12, 12),
                                      decoration: BoxDecoration(
                                        gradient: LinearGradient(
                                          colors: [
                                            Colors.transparent,
                                            Colors.black.withValues(alpha: 0.75),
                                          ],
                                          begin: Alignment.topCenter,
                                          end: Alignment.bottomCenter,
                                        ),
                                      ),
                                      child: Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.end,
                                        children: [
                                          Expanded(
                                            child: Wrap(
                                              spacing: 8,
                                              runSpacing: 6,
                                              children: [
                                                _chipBadge(
                                                  Icons.place_outlined,
                                                  cidade,
                                                  PainelAdminTheme.laranja,
                                                ),
                                                _chipBadge(
                                                  Icons.payments_outlined,
                                                  valorLinha,
                                                  PainelAdminTheme.roxo,
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  Positioned(
                                    top: 10,
                                    right: 10,
                                    child: Material(
                                      color: Colors.white.withValues(alpha: 0.92),
                                      shape: const CircleBorder(),
                                      elevation: 1,
                                      child: InkWell(
                                        customBorder: const CircleBorder(),
                                        onTap: () {
                                          if (imageUrl.isNotEmpty) {
                                            _deletarBanner(doc.id, imageUrl);
                                          }
                                        },
                                        child: Padding(
                                          padding: const EdgeInsets.all(8),
                                          child: Icon(
                                            Icons.delete_outline_rounded,
                                            color: Colors.red.shade600,
                                            size: 20,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _chipBadge(IconData icon, String text, Color accent) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.35),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: accent),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              text,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.plusJakartaSans(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 11.5,
                height: 1.2,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyState() {
    return Padding(
      padding: const EdgeInsets.all(40),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: PainelAdminTheme.roxo.withValues(alpha: 0.07),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.view_carousel_outlined,
              size: 56,
              color: PainelAdminTheme.roxo.withValues(alpha: 0.65),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Nenhum banner na vitrine',
            textAlign: TextAlign.center,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: PainelAdminTheme.dashboardInk,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Publique o primeiro banner para aparecer no carrossel do app.',
            textAlign: TextAlign.center,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 14,
              height: 1.45,
              color: PainelAdminTheme.textoSecundario,
            ),
          ),
          const SizedBox(height: 28),
          FilledButton.icon(
            onPressed: () => _mostrarModalBanner(),
            icon: const Icon(Icons.add_rounded),
            label: Text(
              'Criar primeiro banner',
              style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w800),
            ),
            style: FilledButton.styleFrom(
              backgroundColor: PainelAdminTheme.laranja,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
