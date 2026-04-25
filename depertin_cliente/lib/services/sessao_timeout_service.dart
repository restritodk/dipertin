import 'package:shared_preferences/shared_preferences.dart';

/// Controla a duração máxima de uma sessão logada no app.
///
/// Política de segurança: o usuário é obrigado a re-autenticar a cada
/// [duracaoMaximaSessao] (24h por padrão). Isso minimiza o risco de
/// acesso indevido quando o aparelho é perdido, emprestado ou
/// simplesmente ficou aberto por muito tempo sem uso.
///
/// Como funciona:
///   - Ao login bem-sucedido, chame [registrarLoginAgora].
///   - O `AppGuard` verifica periodicamente (e nos ciclos de lifecycle
///     `resumed`) através de [sessaoExpirada]. Se expirou, ele desloga.
///
/// **Importante**: este serviço NÃO depende do servidor. É um controle
/// client-side simples. Para validação remota de tokens (conta
/// desabilitada/removida), o `AppGuard` já faz `user.reload()`.
class SessaoTimeoutService {
  SessaoTimeoutService._();

  static const String _kPrefUltimoLoginMs = 'sessao.ultimo_login_ms';

  /// Duração máxima antes de forçar re-login.
  ///
  /// Pensada pra balancear segurança e comodidade: 24h permite operar
  /// um turno completo sem reautenticar, mas nunca mais do que isso.
  static const Duration duracaoMaximaSessao = Duration(hours: 24);

  /// Grava o instante atual como o "início da sessão". Chame isso após
  /// qualquer login real no Firebase Auth (e-mail+senha, Google,
  /// biometria, etc.).
  static Future<void> registrarLoginAgora() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(
        _kPrefUltimoLoginMs,
        DateTime.now().millisecondsSinceEpoch,
      );
    } catch (_) {
      // SharedPrefs indisponível em ambientes de teste/desktop —
      // seguir silenciosamente (o guard vai tratar como "sem sessão
      // registrada" e pedir re-login).
    }
  }

  /// Garante um instante de referência local quando há usuário logado
  /// no Firebase mas ainda não foi gravado timestamp (p.ex. após
  /// [limparSessao] + novo login, o [authStateChanges] do AppGuard pode
  /// correr *antes* de [registrarLoginAgora] no LoginScreen).
  ///
  /// Sem isso, [sessaoExpirada] com `ms == null` podia sinalizar "expirado"
  /// e o guard fazia `signOut` de novo de imediato.
  static Future<void> garantirTimestampSessaoSeAusente() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getInt(_kPrefUltimoLoginMs) == null) {
        await prefs.setInt(
          _kPrefUltimoLoginMs,
          DateTime.now().millisecondsSinceEpoch,
        );
      }
    } catch (_) {}
  }

  /// Retorna `true` se a sessão atual já passou de [duracaoMaximaSessao]
  /// desde o último [registrarLoginAgora].
  ///
  /// Se não há registro (`ms == null`), retorna `false` — a ausência
  /// significa "ainda não medimos" (corrida pós-login / primeiro paint),
  /// não "forçar logout". O AppGuard chama [garantirTimestampSessaoSeAusente]
  /// antes de avaliar, para o relógio de 24h passar a contar a partir
  /// da primeira oportunidade com utilizador autenticado.
  static Future<bool> sessaoExpirada() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final ms = prefs.getInt(_kPrefUltimoLoginMs);
      if (ms == null) {
        return false;
      }
      final ultimoLogin = DateTime.fromMillisecondsSinceEpoch(ms);
      final agora = DateTime.now();
      return agora.difference(ultimoLogin) >= duracaoMaximaSessao;
    } catch (_) {
      // Em caso de falha ao acessar SharedPrefs, sê permissivo:
      // não corta uma sessão legítima por causa de um erro de IO
      // transitório.
      return false;
    }
  }

  /// Limpa o timestamp da sessão. Chamado ao fazer signOut explícito
  /// (user clica em "Sair") para que, se o usuário voltar sem logar,
  /// caia direto no LoginScreen.
  static Future<void> limparSessao() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kPrefUltimoLoginMs);
    } catch (_) {}
  }

  /// Tempo restante até a sessão expirar. Útil para exibir mensagens
  /// como "sua sessão expira em 2h". Retorna `Duration.zero` se já
  /// expirada.
  static Future<Duration> tempoRestante() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final ms = prefs.getInt(_kPrefUltimoLoginMs);
      if (ms == null) return Duration.zero;
      final ultimoLogin = DateTime.fromMillisecondsSinceEpoch(ms);
      final fim = ultimoLogin.add(duracaoMaximaSessao);
      final agora = DateTime.now();
      if (!fim.isAfter(agora)) return Duration.zero;
      return fim.difference(agora);
    } catch (_) {
      return Duration.zero;
    }
  }
}
