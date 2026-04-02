# DiPertin - App Cliente

<p align="center">
  <img src="assets/logo.png" alt="DiPertin Logo" width="180"/>
</p>

<p align="center">
  <strong>Marketplace e delivery local</strong> — compre, venda e entregue na sua cidade.
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Flutter-3.11+-02569B?logo=flutter&logoColor=white" alt="Flutter"/>
  <img src="https://img.shields.io/badge/Dart-3.11+-0175C2?logo=dart&logoColor=white" alt="Dart"/>
  <img src="https://img.shields.io/badge/Firebase-Backend-FFCA28?logo=firebase&logoColor=black" alt="Firebase"/>
  <img src="https://img.shields.io/badge/Mercado%20Pago-Pagamentos-00B1EA?logo=mercadopago&logoColor=white" alt="Mercado Pago"/>
</p>

---

## Sobre

O **DiPertin** é uma aplicação mobile (Android/iOS) que conecta **clientes**, **lojistas** e **entregadores** numa única plataforma de comércio e delivery local. Cada perfil tem a sua experiência dedicada dentro do mesmo app.

## Funcionalidades

### Cliente
- Vitrine com produtos e lojas da região
- Busca por produtos e serviços
- Carrinho de compras persistente
- Checkout com múltiplas formas de pagamento (PIX, saldo, dinheiro, Mercado Pago)
- Acompanhamento de pedidos em tempo real
- Chat com a loja sobre o pedido
- Gestão de endereços de entrega
- Suporte via chat

### Lojista
- Dashboard com visão geral do negócio
- Gestão completa de pedidos (aceitar, preparar, despachar)
- Catálogo de produtos (criar, editar, remover)
- Configurações da loja (horários, taxas, endereço)
- Visualização de avaliações dos clientes

### Entregador
- Dashboard com pedidos disponíveis para entrega
- Mapa com navegação até o destino
- Carteira digital com saldo e histórico de ganhos
- Histórico completo de entregas realizadas

### Utilidades
- Vagas de emprego locais
- Achados e perdidos da comunidade
- Eventos da cidade

## Arquitetura

```
lib/
├── main.dart                    # Entrada, Firebase, FCM, navegação
├── firebase_options.dart        # Configuração Firebase (gerado)
├── models/
│   ├── user_model.dart          # Modelo de utilizador
│   ├── product_model.dart       # Modelo de produto
│   ├── cart_item_model.dart     # Modelo de item do carrinho
│   └── banner_model.dart        # Modelo de banner promocional
├── providers/
│   └── cart_provider.dart       # Estado do carrinho (Provider + SharedPreferences)
└── screens/
    ├── auth/                    # Login e registo
    ├── cliente/                 # Vitrine, carrinho, checkout, pedidos, chat
    ├── lojista/                 # Dashboard, pedidos, produtos, config, avaliações
    ├── entregador/              # Dashboard, mapa, carteira, histórico
    ├── comum/                   # Perfil e edição de perfil
    └── utilidades/              # Vagas, achados, eventos
```

## Cloud Functions

O diretório `functions/` contém duas Cloud Functions (Node.js 20) que respondem a eventos do Firestore:

| Função | Trigger | Descrição |
|--------|---------|-----------|
| `notificarNovoPedido` | `onCreate` em `pedidos/{id}` | Envia push FCM ao lojista quando um novo pedido é criado |
| `notificarEntregadoresPedidoPronto` | `onUpdate` em `pedidos/{id}` | Notifica todos os entregadores quando um pedido está pronto para recolha |

## Stack Tecnológica

| Camada | Tecnologia |
|--------|------------|
| Framework | Flutter (Dart ^3.11) |
| Estado | Provider |
| Backend | Firebase (Firestore, Auth, Storage, Messaging) |
| Funções servidor | Cloud Functions (Node.js 20) |
| Pagamentos | Mercado Pago (API REST) |
| Geolocalização | Geolocator + Geocoding |
| Notificações | FCM + Flutter Local Notifications |
| Autenticação social | Google Sign-In |

## Pré-requisitos

- Flutter SDK ^3.11
- Dart SDK ^3.11
- Android Studio ou VS Code com extensões Flutter
- Conta Firebase com projeto configurado
- Node.js 20 (para Cloud Functions)

## Instalação

```bash
# Clonar o repositório
git clone https://github.com/sigadepertin-oss/DiPertin.git
cd DiPertin/depertin_cliente

# Instalar dependências Flutter
flutter pub get

# Instalar dependências das Cloud Functions
cd functions && npm install && cd ..

# Executar no dispositivo/emulador
flutter run
```

## Deploy das Cloud Functions

```bash
cd functions
firebase deploy --only functions
```

## Coleções Firestore

| Coleção | Descrição |
|---------|-----------|
| `users` | Perfis de clientes, lojistas e entregadores |
| `pedidos` | Pedidos com itens, totais e status (subcoleção `mensagens`) |
| `produtos` | Catálogo de produtos por loja |
| `categorias` | Categorias de produtos |
| `banners` | Banners promocionais da vitrine |
| `avaliacoes` | Avaliações de clientes sobre lojas |
| `gateways_pagamento` | Configuração de gateways de pagamento |
| `planos_taxas` | Planos de taxas para lojistas |
| `tabela_fretes` | Tabela de valores de frete por distância |
| `vagas` | Vagas de emprego locais |
| `achados` | Achados e perdidos |
| `eventos` | Eventos da cidade |
| `suporte` | Tickets de suporte (subcoleção `mensagens`) |

## Firebase (regras, Storage, índices)

Não uses palavra-passe em scripts. Autenticação: **`firebase login`** (abre o browser).

1. Instala a CLI: `npm install -g firebase-tools`
2. Na pasta `depertin_cliente`: `firebase login`
3. Publica regras e índices:

```powershell
.\firebase_deploy.ps1           # firestore + storage + functions
.\firebase_deploy.ps1 rules     # só regras Firestore + Storage
.\firebase_deploy.ps1 indexes   # só índices compostos
```

Ficheiros: `firestore.rules`, `firestore.indexes.json`, `storage.rules`, `firebase.json`.

**Nota:** O Firestore e o Storage são criados na [Consola Firebase](https://console.firebase.google.com/) (modo nativo). As regras e índices são versionados neste repositório e aplicados com o deploy.

## Licença

Projeto privado. Todos os direitos reservados.
