// Arquivo: lib/models/user_model.dart

// 1. Criamos primeiro o molde do Endereço
class EnderecoModel {
  String rua;
  String numero;
  String bairro;
  String cidade;
  String estado;
  String cep;
  String complemento;
  double latitude; // Para salvar a posição exata do GPS
  double longitude; // Para salvar a posição exata do GPS

  EnderecoModel({
    required this.rua,
    required this.numero,
    required this.bairro,
    required this.cidade,
    required this.estado,
    required this.cep,
    this.complemento = '',
    this.latitude = 0.0,
    this.longitude = 0.0,
  });

  // Transforma os dados do Firebase para o formato do App
  factory EnderecoModel.fromMap(Map<String, dynamic> map) {
    return EnderecoModel(
      rua: map['rua'] ?? '',
      numero: map['numero'] ?? '',
      bairro: map['bairro'] ?? '',
      cidade: map['cidade'] ?? '',
      estado: map['estado'] ?? '',
      cep: map['cep'] ?? '',
      complemento: map['complemento'] ?? '',
      latitude: (map['latitude'] ?? 0.0).toDouble(),
      longitude: (map['longitude'] ?? 0.0).toDouble(),
    );
  }

  // Transforma os dados do App para salvar no Firebase
  Map<String, dynamic> toMap() {
    return {
      'rua': rua,
      'numero': numero,
      'bairro': bairro,
      'cidade': cidade,
      'estado': estado,
      'cep': cep,
      'complemento': complemento,
      'latitude': latitude,
      'longitude': longitude,
    };
  }
}

// 2. Atualizamos o molde do Usuário
class UserModel {
  String id;
  String nome;
  String email;
  String cpf;
  String role;
  String status;
  EnderecoModel?
  endereco; // <- NOVO: Adicionamos o endereço aqui! O "?" significa que pode ser nulo no momento do cadastro inicial.

  UserModel({
    required this.id,
    required this.nome,
    required this.email,
    required this.cpf,
    this.role = 'cliente',
    this.status = 'aprovado',
    this.endereco,
  });

  // Transforma os dados do Firebase para o formato do App
  factory UserModel.fromMap(Map<String, dynamic> map, String documentId) {
    return UserModel(
      id: documentId,
      nome: map['nome'] ?? '',
      email: map['email'] ?? '',
      cpf: map['cpf'] ?? '',
      role: map['role'] ?? 'cliente',
      status: map['status'] ?? 'aprovado',
      // Aqui nós verificamos se existe um endereço salvo no banco e o convertemos
      endereco: map['endereco'] != null
          ? EnderecoModel.fromMap(map['endereco'])
          : null,
    );
  }

  // Transforma os dados do App para salvar no Firebase
  Map<String, dynamic> toMap() {
    return {
      'nome': nome,
      'email': email,
      'cpf': cpf,
      'role': role,
      'status': status,
      // Se o usuário preencheu o endereço, nós o convertemos para salvar no banco
      'endereco': endereco?.toMap(),
    };
  }
}
