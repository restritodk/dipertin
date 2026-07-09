part of '../assinaturas_inadimplencia_screen.dart';

// ─── Botão Filtros Avançados ────────────────────────────────────────────────

class _BotaoFiltrosAvancados extends StatelessWidget {
  final VoidCallback onTap;
  const _BotaoFiltrosAvancados({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: onTap,
      icon: const Icon(Icons.filter_alt_rounded, size: 18),
      label: const Text(
        'Filtros avançados',
        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      ),
      style: FilledButton.styleFrom(
        backgroundColor: const Color(0xFF6A1B9A),
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
        elevation: 0,
      ),
    );
  }
}

// ─── Modal Premium de Filtros Avançados ─────────────────────────────────────

class _FiltrosAvancadosModal extends StatefulWidget {
  final _FiltrosInadimplencia filtros;
  final List<di.InadimplenciaItem> itens;
  final VoidCallback onAplicar;
  final VoidCallback onLimpar;

  const _FiltrosAvancadosModal({
    required this.filtros,
    required this.itens,
    required this.onAplicar,
    required this.onLimpar,
  });

  @override
  State<_FiltrosAvancadosModal> createState() =>
      _FiltrosAvancadosModalState();
}

class _FiltrosAvancadosModalState
    extends State<_FiltrosAvancadosModal> {
  late _FiltrosInadimplencia _local;
  bool _carregando = true;
  List<String> _planos = [];
  List<String> _cidades = [];
  List<String> _ufs = [];

  @override
  void initState() {
    super.initState();
    _local = _FiltrosInadimplencia();
    _local.search = widget.filtros.search;
    _local.plano = widget.filtros.plano;
    _local.status = widget.filtros.status;
    _local.faixaAtraso = widget.filtros.faixaAtraso;
    _local.cidade = widget.filtros.cidade;
    _local.uf = widget.filtros.uf;
    _carregarDados();
  }

  Future<void> _carregarDados() async {
    setState(() => _carregando = true);

    // 1. Planos — busca real no Firestore
    try {
      final planosSnap = await FirebaseFirestore.instance
          .collection('modulos_planos')
          .orderBy('nome')
          .get();
      _planos = planosSnap.docs
          .map((d) => (d.data()['nome'] as String?) ?? '')
          .where((n) => n.isNotEmpty)
          .toList();
    } catch (_) {
      _planos = [];
    }

    // 2. Cidades, UFs — extrair dos itens reais
    final cidadesSet = <String>{};
    final ufsSet = <String>{};

    for (final item in widget.itens) {
      if (item.cliente != null) {
        if (item.cliente!.addressCity.isNotEmpty) {
          cidadesSet.add(item.cliente!.addressCity);
        }
        if (item.cliente!.addressState.isNotEmpty) {
          ufsSet.add(item.cliente!.addressState.toUpperCase());
        }
      }
    }

    _cidades = cidadesSet.toList()..sort();
    _ufs = ufsSet.toList()..sort();

    setState(() => _carregando = false);
  }

  static const _statusOptions = [
    '',
    'Em atraso',
    'Vence hoje',
    'Paga',
    'Cobrado',
    'Renegociado',
  ];
  static const _statusLabels = [
    'Todos',
    'Em atraso',
    'Vence hoje',
    'Paga',
    'Cobrado',
    'Renegociado',
  ];

  static const _faixaOptions = [
    '',
    '1-7',
    '8-15',
    '16-30',
    '30+',
  ];
  static const _faixaLabels = [
    'Todas',
    '1 a 7 dias',
    '8 a 15 dias',
    '16 a 30 dias',
    'Acima de 30 dias',
  ];

  @override
  Widget build(BuildContext context) {
    final tela = MediaQuery.of(context).size;
    final larga = tela.width > 800;
    final larguraModal = larga ? 680.0 : tela.width * 0.92;
    final alturaModal = larga ? tela.height * 0.88 : tela.height * 0.92;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      backgroundColor: Colors.transparent,
      child: SizedBox(
        width: larguraModal,
        child: Container(
          height: alturaModal,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.12),
                blurRadius: 30,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            children: [
              // ── Header ────────────────────────────────────────────
              _buildHeader(),
              // ── Corpo scrollável ──────────────────────────────────
              Expanded(
                child: _carregando
                    ? _buildLoading()
                    : SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
                        child: _buildForm(),
                      ),
              ),
              // ── Footer ────────────────────────────────────────────
              _buildFooter(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Colors.grey.shade200),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF6A1B9A), Color(0xFF8E24AA)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.filter_alt_rounded,
              color: Colors.white,
              size: 20,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Filtros avançados',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF1A1A2E),
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Refine a busca por cobranças, planos, status e localização.',
                  style: TextStyle(
                    fontSize: 13,
                    color: const Color(0xFF64748B),
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close_rounded),
            style: IconButton.styleFrom(
              backgroundColor: Colors.grey.shade100,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoading() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 36,
            height: 36,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              color: Color(0xFF6A1B9A),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Carregando filtros...',
            style: TextStyle(
              fontSize: 14,
              color: const Color(0xFF64748B),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Busca
        _buildSearchField(),
        const SizedBox(height: 16),

        // Grid 2x2
        Row(
          children: [
            Expanded(
              child: _buildDropdown(
                label: 'Plano',
                value: _local.plano,
                items: _planos.isEmpty ? [''] : ['', ..._planos],
                labels: _planos.isEmpty ? ['Nenhum'] : ['Todos', ..._planos],
                onChanged: (v) => setState(() => _local.plano = v),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildDropdown(
                label: 'Status',
                value: _local.status,
                items: _statusOptions,
                labels: _statusLabels,
                onChanged: (v) => setState(() => _local.status = v),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildDropdown(
                label: 'Faixa de atraso',
                value: _local.faixaAtraso,
                items: _faixaOptions,
                labels: _faixaLabels,
                onChanged: (v) => setState(() => _local.faixaAtraso = v),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),

        Row(
          children: [
            Expanded(
              child: _buildDropdown(
                label: 'Cidade',
                value: _local.cidade,
                items: _cidades.isEmpty ? [''] : ['', ..._cidades],
                labels: _cidades.isEmpty ? ['Nenhuma'] : ['Todas', ..._cidades],
                onChanged: (v) => setState(() => _local.cidade = v),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildDropdown(
                label: 'UF',
                value: _local.uf,
                items: _ufs.isEmpty ? [''] : ['', ..._ufs],
                labels: _ufs.isEmpty ? ['Nenhum'] : ['Todos', ..._ufs],
                onChanged: (v) => setState(() => _local.uf = v),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),

        // Indicador de quantos registros serão afetados
        Container(
          margin: const EdgeInsets.only(top: 8),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFFF1E9FF),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.info_outline_rounded,
                size: 18,
                color: Color(0xFF6A1B9A),
              ),
              const SizedBox(width: 8),
              Text(
                'Total de registros disponíveis: ${_contarFiltrados()}',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF1A1A2E),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  int _contarFiltrados() {
    return _aplicarFiltros(widget.itens).length;
  }

  List<di.InadimplenciaItem> _aplicarFiltros(List<di.InadimplenciaItem> lista) {
    return lista.where((item) {
      if (_local.search.isNotEmpty) {
        final q = _local.search.toLowerCase();
        final nome = item.cobranca.clienteNome.toLowerCase();
        final resp = item.cliente?.ownerName.toLowerCase() ?? '';
        final fatura = item.cobranca.fatura.toLowerCase();
        final email = item.cobranca.clienteEmail.toLowerCase();
        if (!nome.contains(q) &&
            !resp.contains(q) &&
            !fatura.contains(q) &&
            !email.contains(q)) {
          return false;
        }
      }
      if (_local.plano.isNotEmpty &&
          !item.cobranca.planoNome
              .toLowerCase()
              .contains(_local.plano.toLowerCase())) {
        return false;
      }
      if (_local.status.isNotEmpty) {
        final s = _local.status;
        final st = item.statusExibicao;
        if (s == 'Em atraso' && st != 'Em atraso' && st != 'Pagamento prometido' && st != 'Em aberto') return false;
        if (s == 'Vence hoje') {
          final hoje = DateTime.now();
          final venc = item.cobranca.vencimento;
          if (venc.year != hoje.year || venc.month != hoje.month || venc.day != hoje.day) return false;
        }
        if (s == 'Paga' && st != 'Paga') return false;
        if (s == 'Cobrado' && st != 'Em atraso' && st != 'Em aberto') return false;
        if (s == 'Renegociado' && st != 'Negociado') return false;
      }
      if (_local.faixaAtraso.isNotEmpty) {
        final dias = item.diasEmAtraso;
        switch (_local.faixaAtraso) {
          case '1-7':
            if (dias < 1 || dias > 7) return false;
            break;
          case '8-15':
            if (dias < 8 || dias > 15) return false;
            break;
          case '16-30':
            if (dias < 16 || dias > 30) return false;
            break;
          case '30+':
            if (dias < 31) return false;
            break;
        }
      }
      if (_local.cidade.isNotEmpty) {
        final cliCidade = item.cliente?.addressCity.toLowerCase() ?? '';
        if (!cliCidade.contains(_local.cidade.toLowerCase())) {
          return false;
        }
      }
      if (_local.uf.isNotEmpty) {
        final ufCli = (item.cliente?.addressState ?? '').toUpperCase();
        if (ufCli != _local.uf.toUpperCase()) {
          return false;
        }
      }
      return true;
    }).toList();
  }

  Widget _buildSearchField() {
    return TextField(
      controller: TextEditingController(text: _local.search),
      decoration: InputDecoration(
        hintText:
            'Pesquisar por nome, responsável, fatura, CPF/CNPJ ou e-mail...',
        hintStyle: const TextStyle(fontSize: 13, color: Color(0xFF94A3B8)),
        prefixIcon: const Icon(Icons.search_rounded, size: 20),
        filled: true,
        fillColor: const Color(0xFFF8F7FC),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        isDense: true,
      ),
      style: const TextStyle(fontSize: 13),
      onChanged: (v) => setState(() => _local.search = v.trim()),
    );
  }

  Widget _buildDropdown({
    required String label,
    required String value,
    required List<String> items,
    required List<String> labels,
    required ValueChanged<String> onChanged,
  }) {
    return DropdownButtonFormField<String>(
      value: items.contains(value) ? value : '',
      decoration: InputDecoration(
        labelText: label,
        labelStyle:
            const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
        filled: true,
        fillColor: const Color(0xFFF8F7FC),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        isDense: true,
      ),
      items: List.generate(items.length, (i) {
        return DropdownMenuItem(
          value: items[i],
          child: Text(labels[i], style: const TextStyle(fontSize: 13)),
        );
      }),
      onChanged: (v) => onChanged(v ?? ''),
      style: const TextStyle(fontSize: 13, color: Color(0xFF1A1A2E)),
      dropdownColor: Colors.white,
      icon: const Icon(Icons.expand_more_rounded, size: 20),
      borderRadius: BorderRadius.circular(12),
    );
  }

  Widget _buildFooter() {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: Colors.grey.shade200),
        ),
      ),
      child: Row(
        children: [
          // Limpar filtros
          OutlinedButton(
            onPressed: () {
              _local.limpar();
              setState(() {});
            },
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF64748B),
              side: BorderSide(color: Colors.grey.shade300),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text(
              'Limpar filtros',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
          const Spacer(),
          // Cancelar
          OutlinedButton(
            onPressed: () => Navigator.pop(context),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF1A1A2E),
              side: BorderSide(color: Colors.grey.shade300),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text(
              'Cancelar',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(width: 10),
          // Aplicar filtros
          FilledButton(
            onPressed: () {
              widget.filtros.search = _local.search;
              widget.filtros.plano = _local.plano;
              widget.filtros.status = _local.status;
              widget.filtros.faixaAtraso = _local.faixaAtraso;
              widget.filtros.cidade = _local.cidade;
              widget.filtros.uf = _local.uf;
              widget.onAplicar();
            },
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF6A1B9A),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              elevation: 0,
            ),
            child: const Text(
              'Aplicar filtros',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
