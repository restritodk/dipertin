import 'package:flutter/material.dart';

import '../../services/conta_exclusao_service.dart';

const Color _roxo = Color(0xFF6A1B9A);
const Color _laranja = Color(0xFFFF8F00);

/// Texto obrigatório do fluxo (LGPD / retenção).
const String _textoRetencaoObrigatorio =
    'Após a confirmação da exclusão, seus dados permanecerão em nosso banco de '
    'dados por 30 dias. Caso você acesse sua conta novamente dentro desse período, '
    'o processo de exclusão será cancelado automaticamente.';

/// Abre o fluxo em 3 etapas: alerta inicial → mensagem obrigatória → confirmação final.
Future<void> abrirFluxoExclusaoConta(BuildContext context) async {
  final passo1 = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => const _DialogoZonaRiscoPasso1(),
  );
  if (passo1 != true || !context.mounted) return;

  final passo2 = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => const _DialogoMensagemObrigatoriaPasso2(),
  );
  if (passo2 != true || !context.mounted) return;

  final passo3 = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => const _DialogoConfirmacaoFinalPasso3(),
  );
  if (passo3 != true || !context.mounted) return;

  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => const Center(
      child: Card(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: _laranja),
              SizedBox(height: 16),
              Text('Processando sua solicitação de exclusão de conta…'),
            ],
          ),
        ),
      ),
    ),
  );

  try {
    await ContaExclusaoService.solicitarExclusaoConta();
    if (!context.mounted) return;
    Navigator.of(context, rootNavigator: true).pop();

    final dataLimite =
        await ContaExclusaoService.obterDataLimiteExclusaoFormatadaPtBr();
    if (!context.mounted) return;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _DialogoSucessoExclusaoAgendada(dataLimite: dataLimite),
    );
    if (!context.mounted) return;

    await ContaExclusaoService.encerrarSessaoERedirecionarParaEntrar(context);
  } catch (e) {
    if (context.mounted) {
      Navigator.of(context, rootNavigator: true).pop();
      final mensagem = e is StateError
          ? e.message
          : 'Não foi possível concluir a solicitação. Verifique a internet e tente novamente.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(mensagem),
          backgroundColor: Colors.red.shade800,
        ),
      );
    }
  }
}

/// Confirmação após o servidor registrar a exclusão agendada (com data limite em pt-BR).
class _DialogoSucessoExclusaoAgendada extends StatelessWidget {
  const _DialogoSucessoExclusaoAgendada({this.dataLimite});

  final String? dataLimite;

  @override
  Widget build(BuildContext context) {
    final temData = dataLimite != null && dataLimite!.trim().isNotEmpty;
    final textoPrazo = temData
        ? 'Se quiser voltar a usar sua conta, você tem até ${dataLimite!} '
            'para cancelar esse processo — basta entrar de novo no app '
            'com seu e-mail e senha antes dessa data.'
        : 'Se quiser voltar a usar sua conta, você pode cancelar esse processo '
            'entrando de novo no app dentro de 30 dias, com seu e-mail e senha.';

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 22, 24, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE8F5E9),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.check_circle_rounded,
                      color: Color(0xFF2E7D32),
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Exclusão agendada',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Text(
                'Sua conta foi programada para exclusão com sucesso.',
                style: TextStyle(
                  fontSize: 15,
                  height: 1.45,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade900,
                ),
              ),
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFE3F2FD),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF90CAF9)),
                ),
                child: Text(
                  textoPrazo,
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.5,
                    color: Colors.blueGrey.shade900,
                  ),
                ),
              ),
              const SizedBox(height: 22),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    backgroundColor: _roxo,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Entendi',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
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

class _DialogoZonaRiscoPasso1 extends StatelessWidget {
  const _DialogoZonaRiscoPasso1();

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF3E0),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.warning_amber_rounded,
                      color: Color(0xFFE65100),
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Zona de risco',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.shade100),
                ),
                child: Text(
                  'Ação crítica · Operação irreversível após o prazo legal de retenção',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.red.shade900,
                  ),
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                'Excluir conta',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: _roxo,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Você está iniciando um processo de exclusão da sua conta no DiPertin.\n\n'
                '• A conta será marcada para exclusão — não será apagada na hora.\n'
                '• Há um período de retenção de 30 dias, conforme nossa política.\n'
                '• Durante esse período, se você entrar de novo, a solicitação será cancelada automaticamente.',
                style: TextStyle(
                  fontSize: 14,
                  height: 1.45,
                  color: Colors.grey.shade800,
                ),
              ),
              const SizedBox(height: 22),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context, false),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        foregroundColor: _roxo,
                        side: const BorderSide(color: _roxo),
                      ),
                      child: const Text('Voltar'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(context, true),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        backgroundColor: _roxo,
                        foregroundColor: Colors.white,
                        elevation: 0,
                      ),
                      child: const Text('Continuar'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DialogoMensagemObrigatoriaPasso2 extends StatefulWidget {
  const _DialogoMensagemObrigatoriaPasso2();

  @override
  State<_DialogoMensagemObrigatoriaPasso2> createState() =>
      _DialogoMensagemObrigatoriaPasso2State();
}

class _DialogoMensagemObrigatoriaPasso2State
    extends State<_DialogoMensagemObrigatoriaPasso2> {
  bool _liECompreendi = false;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Informações obrigatórias',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Leia com atenção antes de continuar.',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF8E1),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFFFB300), width: 1.5),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.amber.shade100.withValues(alpha: 0.6),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: const Text(
                  _textoRetencaoObrigatorio,
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.5,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF5D4037),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              CheckboxListTile(
                value: _liECompreendi,
                onChanged: (v) => setState(() => _liECompreendi = v ?? false),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
                title: const Text(
                  'Li e compreendi as informações acima.',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context, false),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        foregroundColor: _roxo,
                        side: const BorderSide(color: _roxo),
                      ),
                      child: const Text('Voltar'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _liECompreendi
                          ? () => Navigator.pop(context, true)
                          : null,
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        backgroundColor: _laranja,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: Colors.grey.shade300,
                        elevation: 0,
                      ),
                      child: const Text('Prosseguir'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DialogoConfirmacaoFinalPasso3 extends StatelessWidget {
  const _DialogoConfirmacaoFinalPasso3();

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Confirmação final',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'Ao confirmar:\n\n'
                '• Sua conta entrará em processo de exclusão agendada.\n'
                '• Os dados permanecem retidos por 30 dias.\n'
                '• Após esse período, a exclusão poderá se tornar definitiva, '
                'conforme a política do sistema.\n\n'
                'Esta ação não pode ser desfeita com um único toque — só poderá '
                'ser cancelada se você entrar de novo dentro do prazo de 30 dias.',
                style: TextStyle(
                  fontSize: 14,
                  height: 1.45,
                  color: Colors.grey.shade800,
                ),
              ),
              const SizedBox(height: 22),
              OutlinedButton(
                onPressed: () => Navigator.pop(context, false),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  foregroundColor: _roxo,
                  side: const BorderSide(color: _roxo),
                ),
                child: const Text('Cancelar'),
              ),
              const SizedBox(height: 10),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  backgroundColor: const Color(0xFFC62828),
                  foregroundColor: Colors.white,
                  elevation: 0,
                ),
                child: const Text(
                  'Confirmar solicitação de exclusão',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
