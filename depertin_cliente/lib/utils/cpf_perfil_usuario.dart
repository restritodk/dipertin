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

  static bool digitosCnpjValidos(String digitos) {
    if (digitos.length != 14) return false;
    if (RegExp(r'^(\d)\1{13}$').hasMatch(digitos)) return false;
    return true;
  }

  /// Validação completa de CNPJ (Mod 11) a partir de entrada livre (com ou sem máscara).
  static bool cnpjValido(String entrada) {
    final d = somenteDigitos(entrada);
    if (!digitosCnpjValidos(d)) return false;

    const pesos1 = [5, 4, 3, 2, 9, 8, 7, 6, 5, 4, 3, 2];
    var soma = 0;
    for (var i = 0; i < 12; i++) {
      soma += int.parse(d[i]) * pesos1[i];
    }
    var resto = soma % 11;
    final dig1 = resto < 2 ? 0 : 11 - resto;
    if (dig1 != int.parse(d[12])) return false;

    const pesos2 = [6, 5, 4, 3, 2, 9, 8, 7, 6, 5, 4, 3, 2];
    soma = 0;
    for (var i = 0; i < 13; i++) {
      soma += int.parse(d[i]) * pesos2[i];
    }
    resto = soma % 11;
    final dig2 = resto < 2 ? 0 : 11 - resto;
    if (dig2 != int.parse(d[13])) return false;

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
