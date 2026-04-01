# DiPertin

<p align="center">
  <img src="depertin_cliente/assets/logo.png" alt="DiPertin Logo" width="200"/>
</p>

<p align="center">
  <strong>Marketplace e delivery local</strong> — conectando clientes, lojas e entregadores na sua cidade.
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Flutter-3.11+-02569B?logo=flutter&logoColor=white" alt="Flutter"/>
  <img src="https://img.shields.io/badge/Firebase-Backend-FFCA28?logo=firebase&logoColor=black" alt="Firebase"/>
  <img src="https://img.shields.io/badge/Node.js-20-339933?logo=node.js&logoColor=white" alt="Node.js"/>
  <img src="https://img.shields.io/badge/Mercado%20Pago-Pagamentos-00B1EA?logo=mercadopago&logoColor=white" alt="Mercado Pago"/>
</p>

---

## O que é o DiPertin?

O DiPertin é uma plataforma completa de comércio e delivery local. Os **clientes** compram produtos de lojas da sua cidade, os **lojistas** gerem os seus catálogos e pedidos, e os **entregadores** fazem as entregas — tudo dentro de um ecossistema integrado.

## Estrutura do Repositório

```
DiPertin/
├── depertin_cliente/     # App mobile (Android/iOS) — cliente, lojista e entregador
│   ├── lib/              # Código Flutter principal
│   └── functions/        # Cloud Functions (Node.js 20)
└── depertin_web/         # Painel administrativo (Web/Desktop)
    └── lib/              # Código Flutter do admin
```

| Projeto | Descrição | Plataformas |
|---------|-----------|-------------|
| [**depertin_cliente**](./depertin_cliente/) | App principal para clientes, lojistas e entregadores | Android, iOS |
| [**depertin_web**](./depertin_web/) | Painel administrativo para gestão da plataforma | Web, Windows, Linux, macOS |

## Visão Geral da Arquitetura

```
┌─────────────────┐     ┌─────────────────┐
│  App Cliente     │     │  Painel Admin   │
│  (Flutter)       │     │  (Flutter Web)  │
└────────┬────────┘     └────────┬────────┘
         │                       │
         └───────────┬───────────┘
                     │
         ┌───────────▼───────────┐
         │      Firebase         │
         │  ┌─────────────────┐  │
         │  │   Firestore     │  │
         │  │   Auth          │  │
         │  │   Storage       │  │
         │  │   Messaging     │  │
         │  │   Functions     │  │
         │  └─────────────────┘  │
         └───────────┬───────────┘
                     │
         ┌───────────▼───────────┐
         │    Mercado Pago       │
         │    (Pagamentos)       │
         └───────────────────────┘
```

## Stack Tecnológica

| Componente | Tecnologia |
|------------|------------|
| Apps | Flutter (Dart ^3.11) |
| Estado | Provider |
| Base de dados | Cloud Firestore |
| Autenticação | Firebase Auth + Google Sign-In |
| Armazenamento | Firebase Storage |
| Notificações | Firebase Cloud Messaging (FCM) |
| Funções servidor | Cloud Functions (Node.js 20) |
| Pagamentos | Mercado Pago (API REST) |
| Geolocalização | Geolocator + Geocoding |

## Início Rápido

### App Cliente (mobile)

```bash
cd depertin_cliente
flutter pub get
flutter run
```

### Painel Admin (web)

```bash
cd depertin_web
flutter pub get
flutter run -d chrome
```

### Cloud Functions

```bash
cd depertin_cliente/functions
npm install
firebase deploy --only functions
```

## Projeto Firebase

Ambas as aplicações partilham o mesmo projeto Firebase: **`depertin-f940f`**

## Licença

Projeto privado. Todos os direitos reservados.
