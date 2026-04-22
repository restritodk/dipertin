// Arquivo: lib/screens/entregador/configuracoes/configuracoes_entregador_screen.dart

import 'package:flutter/material.dart';

import '../../cliente/meus_enderecos_screen.dart';
import 'acessibilidade_screen.dart';
import 'gerenciar_veiculos_screen.dart';
import 'informacoes_fiscais_screen.dart';
import 'meus_documentos_screen.dart';

const Color _roxo = Color(0xFF6A1B9A);
const Color _laranja = Color(0xFFFF8F00);

class ConfiguracoesEntregadorScreen extends StatelessWidget {
  const ConfiguracoesEntregadorScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F7),
      appBar: AppBar(
        title: const Text(
          'Configurações',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: _roxo,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 12),
        children: [
          _SecaoConfig(
            titulo: 'Gerenciar',
            icone: Icons.tune_rounded,
            itens: [
              _ItemConfig(
                icone: Icons.home_work_outlined,
                titulo: 'Editar Endereço',
                subtitulo: 'Endereço residencial e cidade de atuação',
                destino: const MeusEnderecosScreen(),
              ),
              _ItemConfig(
                icone: Icons.accessibility_new_rounded,
                titulo: 'Acessibilidade',
                subtitulo: 'Audição, vibração e flash de solicitações',
                destino: const AcessibilidadeScreen(),
              ),
            ],
          ),
          _SecaoConfig(
            titulo: 'Veículo',
            icone: Icons.two_wheeler_rounded,
            itens: [
              _ItemConfig(
                icone: Icons.directions_bike_rounded,
                titulo: 'Gerenciar Veículos',
                subtitulo: 'Cadastre, edite e selecione o veículo ativo',
                destino: const GerenciarVeiculosScreen(),
              ),
            ],
          ),
          _SecaoConfig(
            titulo: 'Documentos',
            icone: Icons.description_outlined,
            itens: [
              _ItemConfig(
                icone: Icons.badge_outlined,
                titulo: 'Meus Documentos',
                subtitulo: 'CNH e documentos do veículo',
                destino: const MeusDocumentosScreen(),
              ),
            ],
          ),
          _SecaoConfig(
            titulo: 'Dinheiro',
            icone: Icons.account_balance_wallet_outlined,
            itens: [
              _ItemConfig(
                icone: Icons.insert_chart_outlined_rounded,
                titulo: 'Informações Fiscais',
                subtitulo: 'Resumos anual e mensal das suas corridas',
                destino: const InformacoesFiscaisScreen(),
              ),
            ],
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _SecaoConfig extends StatelessWidget {
  final String titulo;
  final IconData icone;
  final List<_ItemConfig> itens;

  const _SecaoConfig({
    required this.titulo,
    required this.icone,
    required this.itens,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 8, left: 4),
            child: Row(
              children: [
                Icon(icone, size: 20, color: _laranja),
                const SizedBox(width: 8),
                Text(
                  titulo.toUpperCase(),
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: _laranja,
                    letterSpacing: 1.1,
                  ),
                ),
              ],
            ),
          ),
          Material(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            clipBehavior: Clip.antiAlias,
            elevation: 0,
            child: Column(
              children: [
                for (int i = 0; i < itens.length; i++) ...[
                  itens[i],
                  if (i < itens.length - 1)
                    const Divider(
                      height: 1,
                      indent: 56,
                      color: Color(0xFFEEEEEE),
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ItemConfig extends StatelessWidget {
  final IconData icone;
  final String titulo;
  final String? subtitulo;
  final Widget destino;

  const _ItemConfig({
    required this.icone,
    required this.titulo,
    required this.destino,
    this.subtitulo,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: _roxo.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icone, color: _roxo, size: 22),
      ),
      title: Text(
        titulo,
        style: const TextStyle(
          fontWeight: FontWeight.w600,
          color: Colors.black87,
        ),
      ),
      subtitle: subtitulo == null
          ? null
          : Text(
              subtitulo!,
              style: const TextStyle(fontSize: 12, color: Colors.black54),
            ),
      trailing: const Icon(Icons.chevron_right_rounded, color: Colors.black38),
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => destino),
        );
      },
    );
  }
}
