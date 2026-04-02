import 'package:depertin_web/widgets/botao_suporte_flutuante.dart';
import 'package:depertin_web/utils/admin_perfil.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
// Biblioteca necessária para abrir PDFs em nova aba
import 'package:url_launcher/url_launcher.dart';
import '../widgets/sidebar_menu.dart';

class LojasScreen extends StatefulWidget {
  const LojasScreen({super.key});

  @override
  State<LojasScreen> createState() => _LojasScreenState();
}

class _LojasScreenState extends State<LojasScreen> {
  final Color diPertinRoxo = const Color(0xFF6A1B9A);
  final Color diPertinLaranja = const Color(0xFFFF8F00);

  // Variáveis para controlar as permissões do AdminCity
  String _tipoUsuarioLogado = 'master';
  List<String> _cidadesDoGerente = [];

  @override
  void initState() {
    super.initState();
    _buscarDadosDoGestor();
  }

  // === BUSCA DADOS DO GESTOR LOGADO (CADEADO DE SEGURANÇA) ===
  Future<void> _buscarDadosDoGestor() async {
    User? user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      try {
        final docSnap = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();

        if (docSnap.exists) {
          var dados = docSnap.data()!;
          if (mounted) {
            setState(() {
              _tipoUsuarioLogado = perfilAdministrativo(dados);
              _cidadesDoGerente = List<String>.from(
                dados['cidades_gerenciadas'] ?? [],
              );
            });
          }
        }
      } catch (e) {
        debugPrint("Erro ao carregar permissão: $e");
      }
    }
  }

  // === ALTERAR STATUS DA LOJA COM MOTIVO DE RECUSA ===
  Future<void> _alterarStatusLoja(
    String id,
    String novoStatus, {
    String? motivo,
  }) async {
    Map<String, dynamic> dadosUpdate = {'status_loja': novoStatus};

    // Se tiver motivo, salva no banco. Se for aprovada, apaga o motivo antigo.
    if (motivo != null && motivo.isNotEmpty) {
      dadosUpdate['motivo_recusa'] = motivo;
    } else if (novoStatus == 'Aprovada') {
      dadosUpdate['motivo_recusa'] = FieldValue.delete();
    }

    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(id)
          .update(dadosUpdate);

      if (!mounted) return;
      mostrarSnackPainel(
        context,
        mensagem: 'Status alterado para $novoStatus!',
      );
    } on FirebaseException catch (e) {
      debugPrint('Firestore ao alterar loja: ${e.code} ${e.message}');
      if (!mounted) return;
      mostrarSnackPainel(
        context,
        erro: true,
        mensagem: e.code == 'permission-denied'
            ? 'Sem permissão. No Firestore defina role ou tipoUsuario como master ou master_city e faça deploy das regras.'
            : 'Erro ao salvar: ${e.message ?? e.code}',
      );
    } catch (e) {
      debugPrint('Erro ao alterar status da loja: $e');
      if (!mounted) return;
      mostrarSnackPainel(
        context,
        erro: true,
        mensagem: 'Erro ao salvar: $e',
      );
    }
  }

  // === MODAL PARA DIGITAR O MOTIVO DA RECUSA DA LOJA ===
  void _mostrarModalRecusa(String id, String nomeLoja) {
    TextEditingController motivoC = TextEditingController();
    bool isSalvando = false;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateModal) {
            return AlertDialog(
              title: Text(
                "Recusar / Bloquear: $nomeLoja",
                style: const TextStyle(
                  color: Colors.red,
                  fontWeight: FontWeight.bold,
                ),
              ),
              content: SizedBox(
                width: 400,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      "Informe o motivo da recusa. O lojista verá esta mensagem no aplicativo para poder corrigir.",
                    ),
                    const SizedBox(height: 15),
                    TextField(
                      controller: motivoC,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText:
                            "Motivo (Ex: CNPJ inválido, Comprovante ilegível...)",
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text("Cancelar"),
                ),
                ElevatedButton(
                  onPressed: isSalvando
                      ? null
                      : () async {
                          if (motivoC.text.trim().isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  "Você precisa digitar um motivo!",
                                ),
                                backgroundColor: Colors.red,
                              ),
                            );
                            return;
                          }
                          setStateModal(() => isSalvando = true);

                          // Chama a função passando o status bloqueada e o motivo digitado
                          await _alterarStatusLoja(
                            id,
                            'bloqueada',
                            motivo: motivoC.text.trim(),
                          );

                          if (context.mounted) Navigator.pop(context);
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                  ),
                  child: isSalvando
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : const Text("Confirmar Recusa"),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // === HELPER PARA DETECTAR SE O LINK É PDF ===
  bool _ehPdf(String? url) {
    if (url == null) return false;
    final uri = Uri.parse(url);
    final path = uri.path.toLowerCase();
    return path.endsWith('.pdf');
  }

  // === O VISUALIZADOR DE FOTOS (ZOOM TOTAL E TOTALMENTE SOLTO) ===
  void _mostrarImagemAmpliada(String url, String titulo) {
    showDialog(
      context: context,
      builder: (context) {
        return Dialog.fullscreen(
          backgroundColor: Colors.black.withOpacity(0.9),
          child: Stack(
            children: [
              // Área de Zoom Interativo
              InteractiveViewer(
                panEnabled: true,
                scaleEnabled: true,
                minScale: 0.1,
                maxScale: 8,
                boundaryMargin: const EdgeInsets.all(500),
                child: Center(
                  child: Image.network(
                    url,
                    fit: BoxFit.contain,
                    loadingBuilder: (context, child, progress) {
                      if (progress == null) return child;
                      return const Center(
                        child: CircularProgressIndicator(color: Colors.white),
                      );
                    },
                  ),
                ),
              ),

              // Barra superior com título e botão de fechar
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 15,
                  ),
                  color: Colors.black54,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        titulo,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(
                          Icons.close,
                          color: Colors.white,
                          size: 28,
                        ),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                ),
              ),

              // Dica na parte inferior
              Positioned(
                bottom: 20,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 15,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text(
                      "Use a roda do rato ou pinça para zoom. Arraste para mover.",
                      style: TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // === MODAL PARA VER DOCUMENTOS DA LOJA ===
  void _mostrarDocumentosModal(Map<String, dynamic> dados) {
    String nomeLoja = dados['loja_nome'] ?? 'Loja sem nome';
    // === MÁGICA AQUI: Lê se é CPF ou CNPJ (se não tiver, assume CNPJ por padrão antigo) ===
    String tipoDoc = dados['loja_tipo_documento'] ?? 'CNPJ';

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(
            "Documentos: $nomeLoja",
            style: TextStyle(color: diPertinRoxo, fontWeight: FontWeight.bold),
          ),
          content: SizedBox(
            width: 700,
            height: 600,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Dica de uso
                  Container(
                    padding: const EdgeInsets.all(10),
                    margin: const EdgeInsets.only(bottom: 20),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.blue.shade100),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.info_outline, color: Colors.blue, size: 20),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            "Clique nas imagens para zoom em ecrã inteiro. PDFs abrirão em uma nova aba do navegador.",
                            style: TextStyle(fontSize: 13, color: Colors.blue),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Seções de documentos
                  _buildSessaoDocumento(
                    "Documento Pessoal (RG/CNH)",
                    dados['loja_url_doc_pessoal'],
                  ),

                  // === MOSTRA A VITRINE SE FOR CPF OU O CNPJ SE FOR EMPRESA ===
                  if (tipoDoc == 'CPF')
                    _buildSessaoDocumento(
                      "Foto da Vitrine / Local de Venda",
                      dados['loja_url_vitrine'],
                    )
                  else
                    _buildSessaoDocumento(
                      "CNPJ / Contrato Social",
                      dados['loja_url_cnpj'],
                    ),

                  _buildSessaoDocumento(
                    "Comprovante de Endereço",
                    dados['loja_url_endereco'],
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Fechar Visualizador"),
            ),
          ],
        );
      },
    );
  }

  // Widget auxiliar inteligente: detecta se é PDF ou Imagem e monta o visual
  Widget _buildSessaoDocumento(String titulo, String? url) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 25),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            titulo,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 10),

          if (url == null || url.trim().isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.grey.shade200,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: const Text(
                "Documento não enviado pelo lojista.",
                style: TextStyle(
                  color: Colors.grey,
                  fontStyle: FontStyle.italic,
                ),
              ),
            )
          else if (_ehPdf(url))
            // === VISUAL DO PDF ===
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.red.shade200),
              ),
              child: Row(
                children: [
                  const Icon(Icons.picture_as_pdf, size: 40, color: Colors.red),
                  const SizedBox(width: 20),
                  const Expanded(
                    child: Text(
                      "Este documento é um arquivo PDF.",
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  ElevatedButton.icon(
                    onPressed: () async {
                      final Uri uri = Uri.parse(url);
                      if (!await launchUrl(
                        uri,
                        mode: LaunchMode.externalApplication,
                      )) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text("Não foi possível abrir o PDF."),
                              backgroundColor: Colors.red,
                            ),
                          );
                        }
                      }
                    },
                    icon: const Icon(Icons.open_in_new, size: 16),
                    label: const Text("Abrir PDF"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              ),
            )
          else
            // === VISUAL DA IMAGEM (COM CLIQUE PARA ZOOM) ===
            GestureDetector(
              onTap: () => _mostrarImagemAmpliada(url, titulo),
              child: MouseRegion(
                cursor: SystemMouseCursors.zoomIn,
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.shade300),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.network(
                      url,
                      width: double.infinity,
                      height: 180,
                      fit: BoxFit.cover,
                      loadingBuilder: (context, child, progress) {
                        if (progress == null) return child;
                        return Container(
                          height: 180,
                          color: Colors.grey.shade100,
                          child: const Center(
                            child: CircularProgressIndicator(),
                          ),
                        );
                      },
                      errorBuilder: (context, error, stackTrace) => Container(
                        padding: const EdgeInsets.all(20),
                        color: Colors.red.shade50,
                        child: const Text(
                          "Erro ao carregar imagem.",
                          style: TextStyle(color: Colors.red),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          const SizedBox(height: 10),
          const Divider(),
        ],
      ),
    );
  }

  // === MODAL PARA ATRIBUIR O PLANO ===
  void _atribuirPlanoModal(
    String lojaId,
    String nomeLoja,
    String? planoAtualId,
    String cidadeDaLoja,
  ) {
    String? planoSelecionado = planoAtualId;
    bool isLoading = false;
    String cidadeFiltro = cidadeDaLoja.trim().toLowerCase();
    if (cidadeFiltro.isEmpty) cidadeFiltro = 'todas';
    List<String> cidadesBusca = ['todas'];
    if (cidadeFiltro != 'todas' && !cidadesBusca.contains(cidadeFiltro)) {
      cidadesBusca.add(cidadeFiltro);
    }

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: Text(
                "Definir Plano: $nomeLoja",
                style: TextStyle(
                  color: diPertinRoxo,
                  fontWeight: FontWeight.bold,
                ),
              ),
              content: SizedBox(
                width: 400,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Filtrando planos para a cidade: ${cidadeDaLoja.toUpperCase()}",
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.blue,
                      ),
                    ),
                    const SizedBox(height: 20),
                    StreamBuilder<QuerySnapshot>(
                      stream: FirebaseFirestore.instance
                          .collection('planos_taxas')
                          .where('publico', isEqualTo: 'lojista')
                          .where('cidade', whereIn: cidadesBusca)
                          .snapshots(),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState ==
                            ConnectionState.waiting) {
                          return const CircularProgressIndicator();
                        }
                        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                          return const Text(
                            "Nenhum plano disponível.",
                            style: TextStyle(color: Colors.red),
                          );
                        }
                        var planos = snapshot.data!.docs;
                        if (planoSelecionado != null &&
                            !planos.any((p) => p.id == planoSelecionado)) {
                          planoSelecionado = null;
                        }
                        return DropdownButtonFormField<String>(
                          initialValue: planoSelecionado,
                          decoration: const InputDecoration(
                            labelText: "Selecione o Plano",
                            border: OutlineInputBorder(),
                          ),
                          items: planos.map((doc) {
                            var p = doc.data() as Map<String, dynamic>;

                            String nomePlano = p['nome'] ?? 'Sem nome';
                            String valorPlano = (p['valor'] ?? 0).toString();
                            String tipoCobranca = p['tipo_cobranca'] == 'fixo'
                                ? 'R\$'
                                : '%';
                            String freqPlano = p['frequencia'] ?? 'venda';

                            return DropdownMenuItem<String>(
                              value: doc.id,
                              child: Text(
                                "$nomePlano ($valorPlano$tipoCobranca / $freqPlano)",
                              ),
                            );
                          }).toList(),
                          onChanged: (val) =>
                              setState(() => planoSelecionado = val),
                        );
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text("Cancelar"),
                ),
                ElevatedButton(
                  onPressed: (isLoading || planoSelecionado == null)
                      ? null
                      : () async {
                          setState(() => isLoading = true);
                          try {
                            await FirebaseFirestore.instance
                                .collection('users')
                                .doc(lojaId)
                                .update({'plano_taxa_id': planoSelecionado});
                            if (context.mounted) {
                              Navigator.pop(context);
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Plano atribuído com sucesso!'),
                                  backgroundColor: Colors.green,
                                ),
                              );
                            }
                          } catch (e) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Erro: $e'),
                                  backgroundColor: Colors.red,
                                ),
                              );
                            }
                          } finally {
                            setState(() => isLoading = false);
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: diPertinLaranja,
                    foregroundColor: Colors.white,
                  ),
                  child: isLoading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : const Text("Salvar Plano"),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // === CONSTRUTOR DA LISTA DE LOJAS ===
  Widget _buildListaLojas(String statusFiltro) {
    Query queryBase = FirebaseFirestore.instance
        .collection('users')
        .where('status_loja', isEqualTo: statusFiltro);

    // === CADEADO DE SEGURANÇA: AdminCity só vê a cidade dele ===
    if (_tipoUsuarioLogado == 'master_city' && _cidadesDoGerente.isNotEmpty) {
      queryBase = queryBase.where('cidade', whereIn: _cidadesDoGerente);
    }

    return StreamBuilder<QuerySnapshot>(
      stream: queryBase.snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return Center(child: Text("Nenhuma loja $statusFiltro encontrada."));
        }

        return ListView.builder(
          padding: const EdgeInsets.all(20),
          itemCount: snapshot.data!.docs.length,
          itemBuilder: (context, index) {
            var doc = snapshot.data!.docs[index];
            var dados = doc.data() as Map<String, dynamic>;
            String nomeDaLoja = dados['loja_nome'] ?? 'Loja Sem Nome';
            String nomeDono = dados['nome'] ?? 'N/A';
            String? planoId = dados['plano_taxa_id'];
            String cidadeDaLoja = dados['cidade'] ?? 'Todas';

            return Card(
              elevation: 2,
              margin: const EdgeInsets.only(bottom: 10),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: statusFiltro == 'aprovada'
                      ? Colors.green[100]
                      : (statusFiltro == 'pendente'
                            ? Colors.orange[100]
                            : Colors.red[100]),
                  child: Icon(
                    Icons.store,
                    color: statusFiltro == 'aprovada'
                        ? Colors.green
                        : (statusFiltro == 'pendente'
                              ? Colors.orange
                              : Colors.red),
                  ),
                ),
                title: Text(
                  nomeDaLoja,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                subtitle: Text(
                  "Cidade: $cidadeDaLoja | Responsável: $nomeDono\nPlano: ${planoId != null ? 'Configurado' : 'Sem Plano'}",
                ),
                isThreeLine: true,
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () => _mostrarDocumentosModal(dados),
                      icon: const Icon(Icons.assignment_ind, size: 16),
                      label: const Text("Docs"),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.blue,
                      ),
                    ),
                    const SizedBox(width: 10),
                    if (statusFiltro == 'aprovada')
                      OutlinedButton.icon(
                        onPressed: () => _atribuirPlanoModal(
                          doc.id,
                          nomeDaLoja,
                          planoId,
                          cidadeDaLoja,
                        ),
                        icon: const Icon(Icons.percent, size: 16),
                        label: const Text("Plano/Taxa"),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: diPertinRoxo,
                        ),
                      ),
                    const SizedBox(width: 10),

                    // === BOTÕES DE AÇÃO COM MENSAGEM DE RECUSA ===
                    if (statusFiltro == 'pendente') ...[
                      IconButton(
                        icon: const Icon(
                          Icons.check_circle,
                          color: Colors.green,
                        ),
                        tooltip: "Aprovar",
                        onPressed: () => _alterarStatusLoja(doc.id, 'aprovada'),
                      ),
                      IconButton(
                        icon: const Icon(Icons.cancel, color: Colors.red),
                        tooltip: "Recusar Cadastro",
                        onPressed: () => _mostrarModalRecusa(
                          doc.id,
                          nomeDaLoja,
                        ), // Chama o Modal!
                      ),
                    ] else if (statusFiltro == 'aprovada') ...[
                      IconButton(
                        icon: const Icon(Icons.block, color: Colors.red),
                        tooltip: "Bloquear Loja",
                        onPressed: () => _mostrarModalRecusa(
                          doc.id,
                          nomeDaLoja,
                        ), // Chama o Modal!
                      ),
                    ] else if (statusFiltro == 'bloqueada') ...[
                      IconButton(
                        icon: const Icon(Icons.restore, color: Colors.green),
                        tooltip: "Desbloquear (Aprovar)",
                        onPressed: () => _alterarStatusLoja(doc.id, 'aprovada'),
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: Colors.grey[100],
        body: Row(
          children: [
            const SidebarMenu(rotaAtual: '/lojas'),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    color: Colors.white,
                    padding: const EdgeInsets.only(
                      top: 30,
                      left: 30,
                      right: 30,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Gestão de Lojas",
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            color: diPertinRoxo,
                          ),
                        ),
                        const Text(
                          "Aprove parceiros e defina os planos de comissão de cada um.",
                          style: TextStyle(color: Colors.grey, fontSize: 16),
                        ),
                        const SizedBox(height: 20),
                        TabBar(
                          labelColor: diPertinRoxo,
                          unselectedLabelColor: Colors.grey,
                          indicatorColor: diPertinLaranja,
                          tabs: const [
                            Tab(
                              icon: Icon(Icons.hourglass_empty),
                              text: "Pendentes",
                            ),
                            Tab(
                              icon: Icon(Icons.check_circle_outline),
                              text: "Aprovadas",
                            ),
                            Tab(icon: Icon(Icons.block), text: "Bloqueadas"),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: TabBarView(
                      children: [
                        _buildListaLojas('pendente'),
                        _buildListaLojas('aprovada'),
                        _buildListaLojas('bloqueada'),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        floatingActionButton: const BotaoSuporteFlutuante(),
      ),
    );
  }
}
