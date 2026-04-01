import 'package:depertin_web/widgets/botao_suporte_flutuante.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:url_launcher/url_launcher.dart';
import '../widgets/sidebar_menu.dart';

class EntregadoresScreen extends StatefulWidget {
  const EntregadoresScreen({super.key});

  @override
  State<EntregadoresScreen> createState() => _EntregadoresScreenState();
}

class _EntregadoresScreenState extends State<EntregadoresScreen> {
  final Color diPertinRoxo = const Color(0xFF6A1B9A);
  final Color diPertinLaranja = const Color(0xFFFF8F00);

  // Variáveis para controlar as permissões do AdminCity
  String _tipoUsuarioLogado = 'superadmin';
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
        QuerySnapshot snap = await FirebaseFirestore.instance
            .collection('users')
            .where('email', isEqualTo: user.email)
            .get();

        if (snap.docs.isNotEmpty) {
          var dados = snap.docs.first.data() as Map<String, dynamic>;
          if (mounted) {
            setState(() {
              _tipoUsuarioLogado =
                  (dados['tipoUsuario'] ?? dados['role'] ?? 'cliente')
                      .toString()
                      .toLowerCase();
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

  // === ALTERAR STATUS COM MOTIVO DE RECUSA ===
  Future<void> _alterarStatusEntregador(
    String id,
    String novoStatus, {
    String? motivo,
  }) async {
    Map<String, dynamic> dadosUpdate = {
      'entregador_status':
          novoStatus, // Usando a nomenclatura correta do seu banco
    };

    // Se tiver motivo, salva no banco. Se for aprovado, apaga o motivo antigo.
    if (motivo != null && motivo.isNotEmpty) {
      dadosUpdate['motivo_recusa'] = motivo;
    } else if (novoStatus == 'aprovado') {
      dadosUpdate['motivo_recusa'] = FieldValue.delete();
    }

    await FirebaseFirestore.instance
        .collection('users')
        .doc(id)
        .update(dadosUpdate);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Status alterado para $novoStatus!'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  // === MODAL PARA DIGITAR O MOTIVO DA RECUSA ===
  void _mostrarModalRecusa(String id, String nomeEntregador) {
    TextEditingController motivoC = TextEditingController();
    bool isSalvando = false;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateModal) {
            return AlertDialog(
              title: Text(
                "Recusar / Bloquear: $nomeEntregador",
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
                      "Informe o motivo da recusa. O entregador verá esta mensagem no aplicativo para poder corrigir.",
                    ),
                    const SizedBox(height: 15),
                    TextField(
                      controller: motivoC,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText:
                            "Motivo (Ex: CNH ilegível, Faltou a placa do veículo...)",
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

                          // Chama a função passando o status bloqueado e o motivo digitado
                          await _alterarStatusEntregador(
                            id,
                            'bloqueado',
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

  // === MODAL PARA VER DOCUMENTOS DO ENTREGADOR ===
  void _mostrarDocumentosModal(Map<String, dynamic> dados) {
    String nomeEntregador = dados['nome'] ?? 'Entregador sem nome';

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(
            "Documentos: $nomeEntregador",
            style: TextStyle(color: diPertinRoxo, fontWeight: FontWeight.bold),
          ),
          content: SizedBox(
            width: 600,
            height: 500,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
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
                            "Clique nas fotos para zoom em ecrã inteiro. PDFs abrirão em uma nova aba.",
                            style: TextStyle(fontSize: 13, color: Colors.blue),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // === OS CAMPOS REAIS DO SEU BANCO DE DADOS ===
                  _buildSessaoDocumento(
                    "Documento Pessoal (CNH/RG)",
                    dados['url_doc_pessoal'],
                  ),
                  _buildSessaoDocumento(
                    "Documento do Veículo (CRLV)",
                    dados['url_crlv'],
                  ),
                  _buildSessaoDocumento(
                    "Foto do Veículo",
                    dados['url_foto_veículo'],
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

  // Widget auxiliar que detecta PDF ou Imagem e monta o visual
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
              ),
              child: const Text(
                "Documento não enviado.",
                style: TextStyle(
                  color: Colors.grey,
                  fontStyle: FontStyle.italic,
                ),
              ),
            )
          else if (_ehPdf(url))
            // === VISUAL DO PDF (SE TIVER .PDF NO LINK) ===
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
                      "Este documento é um PDF.",
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
                              content: Text("Erro ao abrir PDF."),
                              backgroundColor: Colors.red,
                            ),
                          );
                        }
                      }
                    },
                    icon: const Icon(Icons.open_in_new, size: 16),
                    label: const Text("Abrir"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              ),
            )
          else
            // === VISUAL DA FOTO (COM REDE DE SEGURANÇA PARA PDF SEM EXTENSÃO) ===
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
                      height: 150,
                      fit: BoxFit.cover,
                      loadingBuilder: (context, child, progress) {
                        if (progress == null) return child;
                        return Container(
                          height: 150,
                          color: Colors.grey.shade100,
                          child: const Center(
                            child: CircularProgressIndicator(),
                          ),
                        );
                      },
                      // MÁGICA AQUI: Se falhar ao abrir como foto, cria um botão para abrir no navegador!
                      errorBuilder: (context, error, stackTrace) => Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(20),
                        color: Colors.grey.shade100,
                        child: Column(
                          children: [
                            const Icon(
                              Icons.description,
                              color: Colors.grey,
                              size: 40,
                            ),
                            const SizedBox(height: 10),
                            const Text(
                              "Arquivo não pôde ser exibido como foto.\nProvavelmente é um PDF.",
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.grey,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(height: 10),
                            ElevatedButton.icon(
                              onPressed: () => launchUrl(
                                Uri.parse(url),
                                mode: LaunchMode.externalApplication,
                              ),
                              icon: const Icon(Icons.open_in_new, size: 16),
                              label: const Text("Abrir no Navegador"),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.blue,
                                foregroundColor: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          const SizedBox(height: 5),
        ],
      ),
    );
  }

  // === MODAL PARA ATRIBUIR O PLANO DE ENTREGADOR ===
  void _atribuirPlanoModal(
    String entregadorId,
    String nomeEntregador,
    String? planoAtualId,
    String cidadeOrigem,
    String veiculoTipo,
  ) {
    String? planoSelecionado = planoAtualId;
    bool isLoading = false;

    String cidadeFiltro = cidadeOrigem.trim().toLowerCase();
    if (cidadeFiltro.isEmpty) cidadeFiltro = 'todas';
    List<String> cidadesBusca = ['todas'];
    if (cidadeFiltro != 'todas' && !cidadesBusca.contains(cidadeFiltro)) {
      cidadesBusca.add(cidadeFiltro);
    }

    String veiculoFormatado = veiculoTipo.trim().isEmpty
        ? 'Moto'
        : (veiculoTipo[0].toUpperCase() +
              veiculoTipo.substring(1).toLowerCase());

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: Text(
                "Definir Plano: $nomeEntregador",
                style: TextStyle(
                  color: diPertinRoxo,
                  fontWeight: FontWeight.bold,
                ),
              ),
              content: SizedBox(
                width: 450,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "Cidade do Entregador: ${cidadeOrigem.toUpperCase()}",
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.blue,
                              fontSize: 13,
                            ),
                          ),
                          Text(
                            "Veículo: $veiculoFormatado",
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.green,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    StreamBuilder<QuerySnapshot>(
                      stream: FirebaseFirestore.instance
                          .collection('planos_taxas')
                          .where('publico', isEqualTo: 'entregador')
                          .where('cidade', whereIn: cidadesBusca)
                          .snapshots(),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState ==
                            ConnectionState.waiting) {
                          return const CircularProgressIndicator();
                        }

                        var planosValidos = [];
                        if (snapshot.hasData) {
                          for (var doc in snapshot.data!.docs) {
                            var p = doc.data() as Map<String, dynamic>;
                            String vPlano = p['veiculo'] ?? 'Todos';
                            if (vPlano == veiculoFormatado ||
                                vPlano == 'Todos') {
                              planosValidos.add(doc);
                            }
                          }
                        }

                        if (planosValidos.isEmpty) {
                          return const Text(
                            "Nenhum plano disponível para esta cidade e veículo.",
                            style: TextStyle(color: Colors.red),
                          );
                        }
                        if (planoSelecionado != null &&
                            !planosValidos.any(
                              (p) => p.id == planoSelecionado,
                            )) {
                          planoSelecionado = null;
                        }

                        return DropdownButtonFormField<String>(
                          isExpanded: true,
                          initialValue: planoSelecionado,
                          decoration: const InputDecoration(
                            labelText: "Selecione o Plano de Comissões",
                            border: OutlineInputBorder(),
                          ),
                          items: planosValidos.map<DropdownMenuItem<String>>((
                            doc,
                          ) {
                            var p = doc.data() as Map<String, dynamic>;

                            // Extraímos os dados para variáveis simples para evitar o erro de const/interpolação
                            String nomePlano = p['nome'] ?? 'Sem nome';
                            String valorPlano = (p['valor'] ?? 0).toString();
                            String tipoCobranca = p['tipo_cobranca'] == 'fixo'
                                ? 'R\$'
                                : '%';
                            String freqPlano = p['frequencia'] == 'venda'
                                ? 'pedido'
                                : (p['frequencia'] ?? '');
                            String veiculoPlano = p['veiculo'] ?? 'Todos';

                            return DropdownMenuItem<String>(
                              value: doc.id,
                              child: Text(
                                "$nomePlano ($valorPlano$tipoCobranca / $freqPlano) - Veículo: $veiculoPlano",
                                style: const TextStyle(fontSize: 13),
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
                                .doc(entregadorId)
                                .update({
                                  'plano_entregador_id': planoSelecionado,
                                });
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
                      : const Text("Atribuir Plano"),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // === CONSTRUTOR DA LISTA DE ENTREGADORES ===
  Widget _buildListaEntregadores(String statusFiltro) {
    // <--- CORRIGIDO AQUI: Voltamos a buscar 'role' = 'entregador' e 'entregador_status'
    Query queryBase = FirebaseFirestore.instance
        .collection('users')
        .where('role', isEqualTo: 'entregador')
        .where('entregador_status', isEqualTo: statusFiltro);

    // === CADEADO DE SEGURANÇA: AdminCity só vê a cidade dele ===
    if (_tipoUsuarioLogado == 'admin_city' && _cidadesDoGerente.isNotEmpty) {
      queryBase = queryBase.where('cidade', whereIn: _cidadesDoGerente);
    }

    return StreamBuilder<QuerySnapshot>(
      stream: queryBase.snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return Center(
            child: Text("Nenhum entregador $statusFiltro encontrado."),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(20),
          itemCount: snapshot.data!.docs.length,
          itemBuilder: (context, index) {
            var doc = snapshot.data!.docs[index];
            var dados = doc.data() as Map<String, dynamic>;

            String nome = dados['nome'] ?? 'Sem Nome';
            String veiculo = dados['veiculoTipo'] ?? 'Moto';
            String placa = dados['placa'] ?? 'S/ Placa';
            String cidade = dados['cidade'] ?? 'Todas';
            String? planoId = dados['plano_entregador_id'];

            return Card(
              elevation: 2,
              margin: const EdgeInsets.only(bottom: 10),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: statusFiltro == 'aprovado'
                      ? Colors.green[100]
                      : (statusFiltro == 'pendente'
                            ? Colors.orange[100]
                            : Colors.red[100]),
                  child: Icon(
                    statusFiltro == 'aprovado'
                        ? Icons.check_circle_outline
                        : Icons.motorcycle,
                    color: statusFiltro == 'aprovado'
                        ? Colors.green
                        : (statusFiltro == 'pendente'
                              ? Colors.orange
                              : Colors.red),
                  ),
                ),
                title: Text(
                  nome,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                subtitle: Text(
                  "Cidade: ${cidade.toUpperCase()} | Veículo: $veiculo ($placa)\nPlano: ${planoId != null ? 'Atribuído' : '⚠️ Sem Plano'}",
                ),
                isThreeLine: true,
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // === BOTÃO DE DOCS ===
                    OutlinedButton.icon(
                      onPressed: () => _mostrarDocumentosModal(dados),
                      icon: const Icon(Icons.assignment_ind, size: 16),
                      label: const Text("Docs"),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.blue,
                      ),
                    ),
                    const SizedBox(width: 10),

                    // === BOTÃO DE PLANO (ESTAVA FALTANDO!) ===
                    if (statusFiltro == 'aprovado')
                      OutlinedButton.icon(
                        onPressed: () => _atribuirPlanoModal(
                          doc.id,
                          nome,
                          planoId,
                          cidade,
                          veiculo,
                        ),
                        icon: const Icon(Icons.percent, size: 16),
                        label: const Text("Plano/Taxa"),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: diPertinRoxo,
                        ),
                      ),
                    if (statusFiltro == 'aprovado') const SizedBox(width: 10),

                    // === BOTÕES DE AÇÃO COM MENSAGEM DE RECUSA ===
                    if (statusFiltro == 'pendente') ...[
                      IconButton(
                        icon: const Icon(
                          Icons.check_circle,
                          color: Colors.green,
                        ),
                        tooltip: "Aprovar",
                        onPressed: () =>
                            _alterarStatusEntregador(doc.id, 'aprovado'),
                      ),
                      IconButton(
                        icon: const Icon(Icons.cancel, color: Colors.red),
                        tooltip: "Recusar Cadastro",
                        onPressed: () =>
                            _mostrarModalRecusa(doc.id, nome), // Chama o Modal!
                      ),
                    ] else if (statusFiltro == 'aprovado') ...[
                      IconButton(
                        icon: const Icon(Icons.block, color: Colors.red),
                        tooltip: "Bloquear Entregador",
                        onPressed: () =>
                            _mostrarModalRecusa(doc.id, nome), // Chama o Modal!
                      ),
                    ] else if (statusFiltro == 'bloqueado') ...[
                      IconButton(
                        icon: const Icon(Icons.restore, color: Colors.green),
                        tooltip: "Desbloquear (Aprovar)",
                        onPressed: () =>
                            _alterarStatusEntregador(doc.id, 'aprovado'),
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
            const SidebarMenu(rotaAtual: '/entregadores'),
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
                          "Gestão de Entregadores",
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            color: diPertinRoxo,
                          ),
                        ),
                        const Text(
                          "Aprove motoboys e defina os planos de comissão deles.",
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
                              text: "Aprovados",
                            ),
                            Tab(icon: Icon(Icons.block), text: "Bloqueados"),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: TabBarView(
                      children: [
                        _buildListaEntregadores('pendente'),
                        _buildListaEntregadores('aprovado'),
                        _buildListaEntregadores('bloqueado'),
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
