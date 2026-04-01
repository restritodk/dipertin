// Arquivo: lib/screens/cliente/search_screen.dart

import 'package:depertin_cliente/screens/utilidades/achados_screen.dart';
import 'package:depertin_cliente/screens/utilidades/eventos_screen.dart';
import 'package:depertin_cliente/screens/utilidades/vagas_screen.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';
import 'product_details_screen.dart';
import 'loja_perfil_screen.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'chat_suporte_screen.dart';
import '../auth/login_screen.dart';

const Color diPertinRoxo = Color(0xFF6A1B9A);
const Color diPertinLaranja = Color(0xFFFF8F00);

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  String _buscaNome = "";
  String? _categoriaSelecionada;
  final TextEditingController _searchController = TextEditingController();

  // === NOVA VARIÁVEL PARA GUARDAR A CIDADE DO USUÁRIO ===
  String _cidadeUsuario = "";

  bool get _isPesquisando =>
      _buscaNome.isNotEmpty || _categoriaSelecionada != null;

  @override
  void initState() {
    super.initState();
    _carregarCidadeUsuario(); // Chama a função assim que a tela abre
  }

  // === FUNÇÃO PARA DESCOBRIR A CIDADE DO CLIENTE LOGADO ===
  Future<void> _carregarCidadeUsuario() async {
    User? user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      DocumentSnapshot doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      if (doc.exists) {
        var dados = doc.data() as Map<String, dynamic>;
        setState(() {
          // Salva a cidade em minúsculo para a busca não falhar com letras maiúsculas
          _cidadeUsuario = (dados['cidade'] ?? '').toString().toLowerCase();
        });
      }
    }
  }

  // ==========================================
  // FUNÇÃO MESTRA DE CONTATO (WhatsApp / Ligação)
  // ==========================================
  Future<void> _abrirContato(
    String telefoneBruto,
    String tipoContato, {
    String? nomeProfissional,
  }) async {
    String numeroLimpo = telefoneBruto.replaceAll(RegExp(r'[^0-9]'), '');

    Future<void> ligar() async {
      final Uri url = Uri.parse('tel:$numeroLimpo');
      if (await canLaunchUrl(url)) await launchUrl(url);
    }

    Future<void> chamarZap() async {
      String zap = numeroLimpo.startsWith('55')
          ? numeroLimpo
          : '55$numeroLimpo';

      String saudacao =
          (nomeProfissional != null && nomeProfissional.isNotEmpty)
          ? "Olá $nomeProfissional! "
          : "Olá! ";
      String texto = Uri.encodeComponent(
        "${saudacao}Vi seu destaque no app DiPertin e gostaria de mais informações sobre o seu serviço.",
      );

      final Uri url = Uri.parse('https://wa.me/$zap?text=$texto');

      if (await canLaunchUrl(url)) {
        await launchUrl(url, mode: LaunchMode.externalApplication);
      }
    }

    if (tipoContato == 'whatsapp') {
      await chamarZap();
    } else if (tipoContato == 'ligacao') {
      await ligar();
    } else {
      if (mounted) {
        showModalBottomSheet(
          context: context,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          builder: (context) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Padding(
                  padding: EdgeInsets.all(15.0),
                  child: Text(
                    "Como deseja entrar em contato?",
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.wechat, color: Colors.green),
                  title: const Text("Enviar Mensagem no WhatsApp"),
                  onTap: () {
                    Navigator.pop(context);
                    chamarZap();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.phone, color: diPertinRoxo),
                  title: const Text("Fazer uma Ligação"),
                  onTap: () {
                    Navigator.pop(context);
                    ligar();
                  },
                ),
              ],
            ),
          ),
        );
      }
    }
  }

  void _falarComSuporteParaAnunciar() {
    User? user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Faça login ou cadastre-se para anunciar!'),
          backgroundColor: diPertinLaranja,
        ),
      );
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const LoginScreen()),
      );
    } else {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const ChatSuporteScreen()),
      );
    }
  }

  void _limparFiltros() {
    setState(() {
      _buscaNome = "";
      _categoriaSelecionada = null;
      _searchController.clear();
      FocusScope.of(context).unfocus();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text(
          "Buscar & Guia da Cidade",
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        backgroundColor: diPertinRoxo,
        elevation: 0,
      ),
      body: Column(
        children: [
          Container(
            color: diPertinRoxo,
            padding: const EdgeInsets.fromLTRB(15, 0, 15, 15),
            child: TextField(
              controller: _searchController,
              autofocus: false,
              onChanged: (val) =>
                  setState(() => _buscaNome = val.toLowerCase()),
              decoration: InputDecoration(
                hintText: "Buscar lanches, produtos ou lojas...",
                prefixIcon: const Icon(Icons.search, color: diPertinRoxo),
                suffixIcon: _isPesquisando
                    ? IconButton(
                        icon: const Icon(Icons.close, color: Colors.red),
                        onPressed: _limparFiltros,
                      )
                    : null,
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(vertical: 0),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(30),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),

          Container(
            color: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 10),
            height: 100,
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('categorias')
                  .orderBy('nome')
                  .snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(
                    child: LinearProgressIndicator(color: diPertinLaranja),
                  );
                }
                var categorias = snapshot.data!.docs;

                return ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  itemCount: categorias.length,
                  itemBuilder: (context, index) {
                    var cat = categorias[index].data() as Map<String, dynamic>;
                    String nome = cat['nome'] ?? '';
                    String imagem = cat['imagem'] ?? '';
                    bool estaSelecionada = _categoriaSelecionada == nome;

                    return GestureDetector(
                      onTap: () {
                        setState(
                          () => _categoriaSelecionada = estaSelecionada
                              ? null
                              : nome,
                        );
                        FocusScope.of(context).unfocus();
                      },
                      child: Container(
                        width: 75,
                        margin: const EdgeInsets.symmetric(horizontal: 5),
                        child: Column(
                          children: [
                            CircleAvatar(
                              radius: 28,
                              backgroundColor: estaSelecionada
                                  ? diPertinLaranja
                                  : Colors.transparent,
                              child: CircleAvatar(
                                radius: 25,
                                backgroundImage: imagem.isNotEmpty
                                    ? NetworkImage(imagem)
                                    : null,
                                backgroundColor: Colors.grey[200],
                                child: imagem.isEmpty
                                    ? const Icon(
                                        Icons.category,
                                        color: Colors.grey,
                                      )
                                    : null,
                              ),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              nome,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: estaSelecionada
                                    ? FontWeight.bold
                                    : FontWeight.w500,
                                color: estaSelecionada
                                    ? diPertinLaranja
                                    : Colors.black87,
                              ),
                              textAlign: TextAlign.center,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),

          Expanded(
            child: _isPesquisando
                ? _buildResultadosPesquisa()
                : _buildGuiaDaCidade(),
          ),
        ],
      ),
    );
  }

  // ==========================================
  // WIDGET: O GUIA DA CIDADE
  // ==========================================
  Widget _buildGuiaDaCidade() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(15),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Serviços em Destaque",
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 110,
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('servicos_destaque')
                  .where('ativo', isEqualTo: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                DateTime agora = DateTime.now();
                var anunciosValidos = snapshot.data!.docs.where((doc) {
                  var data = doc.data() as Map<String, dynamic>;
                  if (data['data_inicio'] == null || data['data_fim'] == null) {
                    return false;
                  }
                  DateTime inicio = (data['data_inicio'] as Timestamp).toDate();
                  DateTime vencimento = (data['data_fim'] as Timestamp)
                      .toDate();

                  // Filtra apenas da cidade do cliente (se ele tiver uma)
                  String cidadeAnuncio = (data['cidade'] ?? '')
                      .toString()
                      .toLowerCase();
                  bool passaCidade =
                      _cidadeUsuario.isEmpty || cidadeAnuncio == _cidadeUsuario;

                  return agora.isAfter(inicio) &&
                      agora.isBefore(vencimento) &&
                      passaCidade;
                }).toList();

                anunciosValidos.sort((a, b) {
                  var dataA = a.data() as Map<String, dynamic>;
                  var dataB = b.data() as Map<String, dynamic>;
                  Timestamp? timeA = dataA['data_criacao'] as Timestamp?;
                  Timestamp? timeB = dataB['data_criacao'] as Timestamp?;
                  if (timeA == null || timeB == null) return 0;
                  return timeB.compareTo(timeA);
                });

                return ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: anunciosValidos.length + 1,
                  itemBuilder: (context, i) {
                    if (i == anunciosValidos.length) {
                      return _buildBannerAnuncieAqui();
                    }

                    var ad = anunciosValidos[i].data() as Map<String, dynamic>;

                    return Container(
                      width: 180,
                      margin: const EdgeInsets.only(right: 15),
                      child: Material(
                        color: Colors.white,
                        elevation: 2,
                        borderRadius: BorderRadius.circular(15),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(15),
                          onTap: () => _abrirContato(
                            ad['telefone'] ?? '',
                            'whatsapp',
                            nomeProfissional: ad['titulo'],
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(12.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  ad['titulo'] ?? 'Profissional',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                    color: diPertinRoxo,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  ad['categoria'] ?? 'Geral',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: diPertinLaranja,
                                    fontWeight: FontWeight.bold,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  "Atua em: ${ad['cidade'].toString().toUpperCase()}",
                                  style: const TextStyle(
                                    fontSize: 9,
                                    color: Colors.grey,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const Spacer(),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(4),
                                      decoration: const BoxDecoration(
                                        color: Colors.green,
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(
                                        Icons.wechat,
                                        color: Colors.white,
                                        size: 12,
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    const Text(
                                      "Chamar",
                                      style: TextStyle(
                                        color: Colors.green,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 11,
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
                  },
                );
              },
            ),
          ),

          const SizedBox(height: 25),

          const Text(
            "Telefones de Emergência",
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _buildEmergenciaBotao(
                  "Polícia",
                  "190",
                  Icons.local_police,
                  Colors.blueGrey,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildEmergenciaBotao(
                  "SAMU",
                  "192",
                  Icons.medical_services,
                  Colors.red,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildEmergenciaBotao(
                  "Bombeiros",
                  "193",
                  Icons.fire_truck,
                  Colors.orange,
                ),
              ),
            ],
          ),

          const SizedBox(height: 25),

          const Text(
            "Acesso Rápido Premium",
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 10),
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('telefones_premium')
                .where('ativo', isEqualTo: true)
                .snapshots(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }

              DateTime agora = DateTime.now();
              var telefonesValidos = snapshot.data!.docs.where((doc) {
                var data = doc.data() as Map<String, dynamic>;
                if (data['data_inicio'] == null ||
                    data['data_vencimento'] == null) {
                  return false;
                }
                DateTime inicio = (data['data_inicio'] as Timestamp).toDate();
                DateTime vencimento = (data['data_vencimento'] as Timestamp)
                    .toDate();

                // Filtra apenas da cidade do cliente (se ele tiver uma)
                String cidadeAnuncio = (data['cidade'] ?? '')
                    .toString()
                    .toLowerCase();
                bool passaCidade =
                    _cidadeUsuario.isEmpty || cidadeAnuncio == _cidadeUsuario;

                return agora.isAfter(inicio) &&
                    agora.isBefore(vencimento) &&
                    passaCidade;
              }).toList();

              if (telefonesValidos.isEmpty) {
                return const Text(
                  "Nenhum parceiro de acesso rápido ativo hoje.",
                  style: TextStyle(color: Colors.grey, fontSize: 12),
                );
              }

              return GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  childAspectRatio: 2.5,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                ),
                itemCount: telefonesValidos.length + 1,
                itemBuilder: (context, i) {
                  if (i == telefonesValidos.length) {
                    return _buildBotaoAnuncieTelefone();
                  }

                  var tel = telefonesValidos[i].data() as Map<String, dynamic>;
                  return InkWell(
                    onTap: () => _abrirContato(
                      tel['telefone'] ?? '',
                      tel['tipo_contato'] ?? 'ligacao',
                    ),
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: diPertinRoxo.withOpacity(0.3),
                        ),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.phone_forwarded,
                            color: diPertinRoxo,
                            size: 24,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  tel['titulo'] ?? '',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(
                                  tel['telefone'] ?? '',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: diPertinRoxo,
                                    fontWeight: FontWeight.bold,
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
          ),

          const SizedBox(height: 25),
          const Text(
            "Utilidade Pública",
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 10),

          _buildUtilidadeItem(
            "Vagas de Emprego",
            "Oportunidades na sua região",
            Icons.work,
            Colors.green,
            () async {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Encontre a sua próxima oportunidade! 🍀',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  backgroundColor: Colors.green,
                  duration: Duration(seconds: 2),
                ),
              );
              await Future.delayed(const Duration(seconds: 1));
              if (mounted) {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const VagasScreen()),
                );
              }
            },
          ),

          _buildUtilidadeItem(
            "Eventos e Festas",
            "O que vai rolar na cidade",
            Icons.event,
            diPertinRoxo,
            () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const EventosScreen()),
              );
            },
          ),

          _buildUtilidadeItem(
            "Achados e Perdidos",
            "Documentos, pets e objetos",
            Icons.search_off,
            diPertinLaranja,
            () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const AchadosScreen()),
              );
            },
          ),

          const SizedBox(height: 30),
        ],
      ),
    );
  }

  Widget _buildBannerAnuncieAqui() {
    return InkWell(
      onTap: _falarComSuporteParaAnunciar,
      borderRadius: BorderRadius.circular(15),
      child: Container(
        width: 260,
        margin: const EdgeInsets.only(right: 15),
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: diPertinLaranja.withOpacity(0.5)),
        ),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: diPertinLaranja.withOpacity(0.2),
              radius: 25,
              child: const Icon(
                Icons.campaign,
                color: diPertinLaranja,
                size: 25,
              ),
            ),
            const SizedBox(width: 15),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    "Anuncie seu Serviço",
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: diPertinLaranja,
                    ),
                  ),
                  Text(
                    "Fale com o suporte",
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBotaoAnuncieTelefone() {
    return InkWell(
      onTap: _falarComSuporteParaAnunciar,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.green.withOpacity(0.5)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          children: [
            Icon(Icons.add_call, color: Colors.green[700], size: 24),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    "Seu Disk Aqui",
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Colors.green[700],
                    ),
                  ),
                  const Text(
                    "Patrocinar espaço",
                    style: TextStyle(fontSize: 10, color: Colors.grey),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmergenciaBotao(
    String titulo,
    String numero,
    IconData icone,
    Color cor,
  ) {
    return InkWell(
      onTap: () => _abrirContato(numero, 'ligacao'),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.grey[300]!),
        ),
        child: Column(
          children: [
            Icon(icone, color: cor, size: 28),
            const SizedBox(height: 5),
            Text(
              titulo,
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUtilidadeItem(
    String titulo,
    String subtitulo,
    IconData icone,
    Color cor,
    VoidCallback onTap,
  ) {
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey[200]!),
      ),
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: cor.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icone, color: cor),
        ),
        title: Text(
          titulo,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
        ),
        subtitle: Text(subtitulo, style: const TextStyle(fontSize: 12)),
        trailing: const Icon(
          Icons.arrow_forward_ios,
          size: 14,
          color: Colors.grey,
        ),
        onTap: onTap,
      ),
    );
  }

  // ==========================================
  // WIDGET: RESULTADOS DA BUSCA (LOJAS + PRODUTOS)
  // ==========================================
  Widget _buildResultadosPesquisa() {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Envolvemos tudo no StreamBuilder de Lojas primeiro para pegar os IDs
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('users')
                .where('role', isEqualTo: 'lojista')
                .snapshots(),
            builder: (context, snapshotLojas) {
              List<String> lojasIdsEncontradas = [];
              Widget lojasWidget = const SizedBox.shrink();

              // Se o usuário digitou algo, vamos buscar as lojas
              if (snapshotLojas.hasData && _buscaNome.isNotEmpty) {
                var lojasEncontradas = snapshotLojas.data!.docs.where((doc) {
                  var l = doc.data() as Map<String, dynamic>;
                  String nomeLoja = (l['loja_nome'] ?? l['nome'] ?? '')
                      .toString()
                      .toLowerCase();
                  String cidadeLoja = (l['cidade'] ?? '')
                      .toString()
                      .toLowerCase();

                  bool passaNome = nomeLoja.contains(_buscaNome);
                  bool passaCidade =
                      _cidadeUsuario.isEmpty || cidadeLoja == _cidadeUsuario;

                  return passaNome && passaCidade;
                }).toList();

                // GUARDA OS IDs DAS LOJAS PARA A BUSCA DOS PRODUTOS LOGO ABAIXO!
                lojasIdsEncontradas = lojasEncontradas
                    .map((e) => e.id)
                    .toList();

                // Desenha o Carrossel de Lojas no Topo
                if (lojasEncontradas.isNotEmpty) {
                  lojasWidget = Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.fromLTRB(15, 15, 15, 5),
                        child: Text(
                          "Lojas Encontradas",
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: diPertinRoxo,
                          ),
                        ),
                      ),
                      SizedBox(
                        height: 120,
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          itemCount: lojasEncontradas.length,
                          itemBuilder: (context, index) {
                            var loja =
                                lojasEncontradas[index].data()
                                    as Map<String, dynamic>;
                            String lojaId = lojasEncontradas[index].id;
                            String nome =
                                loja['loja_nome'] ?? loja['nome'] ?? 'Loja';
                            String foto = loja['foto'] ?? loja['imagem'] ?? '';

                            return GestureDetector(
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => LojaPerfilScreen(
                                    lojistaData: loja,
                                    lojistaId: lojaId,
                                  ),
                                ),
                              ),
                              child: Container(
                                width: 140,
                                margin: const EdgeInsets.symmetric(
                                  horizontal: 5,
                                  vertical: 5,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(15),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.05),
                                      blurRadius: 5,
                                    ),
                                  ],
                                  border: Border.all(
                                    color: diPertinLaranja.withOpacity(0.3),
                                  ),
                                ),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    CircleAvatar(
                                      radius: 25,
                                      backgroundColor: Colors.grey[200],
                                      backgroundImage: foto.isNotEmpty
                                          ? NetworkImage(foto)
                                          : null,
                                      child: foto.isEmpty
                                          ? const Icon(
                                              Icons.store,
                                              color: Colors.grey,
                                            )
                                          : null,
                                    ),
                                    const SizedBox(height: 8),
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8.0,
                                      ),
                                      child: Text(
                                        nome,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 12,
                                        ),
                                        maxLines: 2,
                                        textAlign: TextAlign.center,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      const Divider(height: 30),
                    ],
                  );
                }
              }

              // Retorna a coluna final com Lojas + Produtos
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  lojasWidget, // Mostra as lojas no topo (se encontrar alguma)
                  // 2. RESULTADOS DE PRODUTOS
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 15, vertical: 5),
                    child: Text(
                      "Produtos",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: diPertinRoxo,
                      ),
                    ),
                  ),
                  StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance
                        .collection('produtos')
                        .where('ativo', isEqualTo: true)
                        .snapshots(),
                    builder: (context, snapshotProdutos) {
                      if (snapshotProdutos.connectionState ==
                          ConnectionState.waiting) {
                        return const Center(
                          child: Padding(
                            padding: EdgeInsets.all(20),
                            child: CircularProgressIndicator(),
                          ),
                        );
                      }
                      if (!snapshotProdutos.hasData ||
                          snapshotProdutos.data!.docs.isEmpty) {
                        return const Center(
                          child: Text("Nenhum produto cadastrado."),
                        );
                      }

                      var docs = snapshotProdutos.data!.docs.where((doc) {
                        var p = doc.data() as Map<String, dynamic>;

                        bool passaCategoria =
                            _categoriaSelecionada == null ||
                            p['categoria_nome'] == _categoriaSelecionada;

                        String nomeProduto = (p['nome'] ?? '')
                            .toString()
                            .toLowerCase();
                        String lojistaIdDoProduto = (p['lojista_id'] ?? '')
                            .toString();

                        // === A MÁGICA REAL ACONTECE AQUI ===
                        // Se a busca estiver vazia, mostra todos.
                        // Se não, mostra se o NOME DO PRODUTO bater OU se ele for DESSA LOJA encontrada no passo acima!
                        bool passaNomeOuLoja =
                            _buscaNome.isEmpty ||
                            nomeProduto.contains(_buscaNome) ||
                            lojasIdsEncontradas.contains(lojistaIdDoProduto);

                        String cidadeProduto = (p['cidade'] ?? '')
                            .toString()
                            .toLowerCase();
                        bool passaCidadeProduto =
                            cidadeProduto.isEmpty ||
                            _cidadeUsuario.isEmpty ||
                            cidadeProduto == _cidadeUsuario;

                        return passaCategoria &&
                            passaNomeOuLoja &&
                            passaCidadeProduto;
                      }).toList();

                      if (docs.isEmpty) {
                        return Center(
                          child: Padding(
                            padding: const EdgeInsets.all(30.0),
                            child: Column(
                              children: [
                                Icon(
                                  Icons.search_off,
                                  size: 60,
                                  color: Colors.grey[400],
                                ),
                                const SizedBox(height: 10),
                                const Text(
                                  "Nenhum produto encontrado.",
                                  style: TextStyle(color: Colors.grey),
                                ),
                              ],
                            ),
                          ),
                        );
                      }

                      return GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        padding: const EdgeInsets.all(15),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 2,
                              childAspectRatio: 0.75,
                              crossAxisSpacing: 15,
                              mainAxisSpacing: 15,
                            ),
                        itemCount: docs.length,
                        itemBuilder: (context, index) {
                          var p = docs[index].data() as Map<String, dynamic>;
                          p['id'] = docs[index].id;
                          String img =
                              (p['imagens'] != null && p['imagens'].isNotEmpty)
                              ? p['imagens'][0]
                              : '';

                          return GestureDetector(
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) =>
                                    ProductDetailsScreen(produto: p),
                              ),
                            ),
                            child: Container(
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(15),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.05),
                                    blurRadius: 5,
                                  ),
                                ],
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: ClipRRect(
                                      borderRadius: const BorderRadius.vertical(
                                        top: Radius.circular(15),
                                      ),
                                      child: Image.network(
                                        img,
                                        width: double.infinity,
                                        fit: BoxFit.cover,
                                        errorBuilder: (c, e, s) => Container(
                                          color: Colors.grey[200],
                                          child: const Icon(
                                            Icons.broken_image,
                                            color: Colors.grey,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.all(10.0),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          p['nome'] ?? '',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 13,
                                          ),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          "R\$ ${(p['preco'] ?? 0.0).toStringAsFixed(2)}",
                                          style: const TextStyle(
                                            color: diPertinLaranja,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 14,
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
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }
}
