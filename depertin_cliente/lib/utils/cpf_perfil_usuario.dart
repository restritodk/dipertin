/// Regras de CPF no perfil: contas Google preenchem uma vez; depois só via suporte.
class CpfPerfilUsuario {
  CpfPerfilUsuario._();

  static String somenteDigitos(String s) => s.replaceAll(RegExp(r'\D'), '');

  /// `true` = não editar CPF no app (alteração via suporte).
  ///
  /// Só bloqueia quando já existe CPF com 11 dígitos salvos. Se o campo estiver
  /// vazio, nunca bloqueia — corrige documentos com `cpf_alteracao_bloqueada: true`
  /// por engano (ex.: conta Google antiga).
  static bool edicaoBloqueada(Map<String, dynamic> userData) {
    final digitos = somenteDigitos('${userData['cpf'] ?? ''}');
    if (digitos.length != 11) return false;

    final flag = userData['cpf_alteracao_bloqueada'];
    if (flag == false) return false;
    if (flag == true) return true;
    return true;
  }

  static bool digitosCpfValidos(String digitos) {
    if (digitos.length != 11) return false;
    if (RegExp(r'^(\d)\1{10}$').hasMatch(digitos)) return false;
    return true;
  }

  /// Validação completa de CPF (Mod 11) a partir de entrada livre (com ou sem máscara).
  /// Retorna `true` apenas quando os 11 dígitos passam no cálculo dos dígitos verificadores.
  static bool cpfValido(String entrada) {
    final d = somenteDigitos(entrada);
    if (!digitosCpfValidos(d)) return false;

    int soma = 0;
    for (int i = 0; i < 9; i++) {
      soma += int.parse(d[i]) * (10 - i);
    }
    int resto = (soma * 10) % 11;
    if (resto == 10) resto = 0;
    if (resto != int.parse(d[9])) return false;

    soma = 0;
    for (int i = 0; i < 10; i++) {
      soma += int.parse(d[i]) * (11 - i);
    }
    resto = (soma * 10) % 11;
    if (resto == 10) resto = 0;
    if (resto != int.parse(d[10])) return false;

    return true;
  }

  static String comMascara11(String onzeDigitos) {
    final d = somenteDigitos(onzeDigitos);
    if (d.length != 11) return onzeDigitos;
    return '${d.substring(0, 3)}.${d.substring(3, 6)}.${d.substring(6, 9)}-${d.substring(9, 11)}';
  }

  /// Texto para lista do perfil.
  static String textoListaPerfil(Map<String, dynamic> userData) {
    final bruto = '${userData['cpf'] ?? ''}'.trim();
    final d = somenteDigitos(bruto);
    if (d.isEmpty) {
      return edicaoBloqueada(userData)
          ? '—'
          : 'Não informado — complete em Editar perfil';
    }
    if (d.length == 11) return comMascara11(d);
    return bruto;
  }
}
