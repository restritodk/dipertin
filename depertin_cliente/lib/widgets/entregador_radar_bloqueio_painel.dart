import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../screens/cliente/chat_suporte_screen.dart';
import '../screens/entregador/configuracoes/entregador_area_perigo_screen.dart';
import '../services/conta_bloqueio_entregador_service.dart';

/// Painel exibido no Radar quando o bloqueio foi iniciado pelo próprio entregador.
class EntregadorRadarBloqueioPainel extends StatelessWidget {
  const EntregadorRadarBloqueioPainel({
    super.key,
    required this.dadosUsuario,
    this.onVoltarPerfil,
  });

  final Map<String, dynamic> dadosUsuario;
  final VoidCallback? onVoltarPerfil;

  static const Color _roxo = Color(0xFF6A1B9A);

  @override
  Widget build(BuildContext context) {
    final exclusao =
        ContaBloqueioEntregadorService.ehExclusaoPerfilSolicitada(dadosUsuario);
    final admin = ContaBloqueioEntregadorService.isBloqueioFinanceiro(
          dadosUsuario,
        ) ||
        (ContaBloqueioEntregadorService.estaBloqueadoParaOperacoes(
              dadosUsuario,
            ) &&
            !ContaBloqueioEntregadorService.podeDesbloquearPeloProprioEntregador(
              dadosUsuario,
            ) &&
            !exclusao);
    final temp =
        ContaBloqueioEntregadorService.isBloqueioTemporarioTipo(dadosUsuario) &&
            !exclusao;
    final podeDesbloquear =
        ContaBloqueioEntregadorService.podeDesbloquearPeloProprioEntregador(
      dadosUsuario,
    );
    final fim = ContaBloqueioEntregadorService.dataFimBloqueio(dadosUsuario);
    final inicio =
        ContaBloqueioEntregadorService.dataInicioBloqueio(dadosUsuario);
    final motivo =
        ContaBloqueioEntregadorService.textoMotivoBloqueio(dadosUsuario);
    final diasExclusao =
        ContaBloqueioEntregadorService.diasRestantesExclusaoPerfil(dadosUsuario);
    final fmt = DateFormat('dd/MM/yyyy');

    final String titulo;
    final String corpo;
    if (exclusao) {
      titulo = 'Exclusão do perfil em andamento';
      corpo =
          'Seu perfil de entregador está em processo de exclusão. '
          'Você não pode acessar o painel de entregas nem receber corridas. '
          'Sua conta de cliente continua ativa para compras no app. '
          'Para voltar a entregar após o prazo, será necessário fazer um novo cadastro de entregador.';
    } else if (admin) {
      titulo = 'Painel de entregas indisponível';
      corpo =
          'O acesso ao painel de entregador foi suspenso pela administração. '
          'Você continua usando o app normalmente como cliente (vitrine, busca e pedidos).';
    } else if (temp) {
      titulo = 'Conta de entregador pausada';
      corpo =
          'Durante o período de pausa você não pode ficar online nem aceitar corridas.';
    } else {
      titulo = 'Conta de entregador bloqueada';
      corpo =
          'Seu perfil de entregador está bloqueado por tempo indeterminado. '
          'Você não pode receber entregas até reativar a conta.';
    }

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: _roxo.withValues(alpha: 0.08),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  exclusao
                      ? Icons.person_remove_outlined
                      : (temp
                          ? Icons.schedule_rounded
                          : Icons.pause_circle_outline_rounded),
                  size: 52,
                  color: _roxo,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                titulo,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF1A1A2E),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                corpo,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 15,
                  height: 1.5,
                  color: Colors.grey.shade800,
                ),
              ),
              if (exclusao && diasExclusao != null) ...[
                const SizedBox(height: 20),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF7ED),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFFDE68A)),
                  ),
                  child: Column(
                    children: [
                      Text(
                        diasExclusao > 0
                            ? '$diasExclusao dia${diasExclusao == 1 ? '' : 's'} restantes'
                            : 'Remoção em processamento',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: Colors.amber.shade900,
                        ),
                      ),
                      if (ContaBloqueioEntregadorService.dataExclusaoPerfilEfetiva(
                              dadosUsuario) !=
                          null)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            'Previsão: ${fmt.format(ContaBloqueioEntregadorService.dataExclusaoPerfilEfetiva(dadosUsuario)!)}',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey.shade700,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
              if (temp && fim != null) ...[
                const SizedBox(height: 16),
                Text(
                  'Liberação prevista: ${fmt.format(fim)}',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade800,
                  ),
                ),
              ],
              if (inicio != null) ...[
                const SizedBox(height: 8),
                Text(
                  'Início: ${fmt.format(inicio)}',
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                ),
              ],
              if (motivo != null && motivo.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  motivo,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey.shade700,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
              const SizedBox(height: 28),
              if (podeDesbloquear)
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const EntregadorAreaPerigoScreen(
                            abrirEmDesbloquear: true,
                          ),
                        ),
                      );
                    },
                    icon: const Icon(Icons.lock_open_rounded),
                    label: const Text(
                      'Desbloquear conta',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: _roxo,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ),
              if (admin) ...[
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const ChatSuporteScreen(),
                        ),
                      );
                    },
                    icon: const Icon(Icons.support_agent_outlined),
                    label: const Text('Falar com o suporte'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFFF8F00),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: onVoltarPerfil,
                  icon: const Icon(Icons.arrow_back_rounded),
                  label: const Text(
                    'Voltar',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: _roxo,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
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
