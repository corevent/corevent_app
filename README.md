# Corevent

Aplicativo Android para descobrir eventos, comprar ingressos e acompanhar suas
atividades. Desenvolvido em Flutter com arquitetura Feature-first + MVVM.

## Funcionalidades

- Cadastro com verificação de e-mail, login e recuperação de senha.
- Descoberta de eventos, busca, categorias e detalhes.
- Favoritos e avaliações.
- Compra de ingressos, pagamento externo e acompanhamento de pedidos.
- Ingressos digitais com QR Code.
- Perfil, foto e alteração de senha.

## Executar

Requer Flutter compatível com Dart `^3.13.4`, Android SDK e um dispositivo ou
emulador Android.

```sh
flutter pub get
dart run build_runner build
flutter run --flavor production
```

A API de produção já está configurada. Para executar em staging:

```sh
flutter run --flavor development --dart-define=COREVENT_API_URL=https://corevent-staging-api-666040325433.us-central1.run.app
```

O app de staging aparece como **dev-Corevent** e pode ser instalado junto com
**Corevent**. O nome depende do flavor; a API é selecionada por `COREVENT_API_URL`
na compilação.

## Verificar

```sh
dart tool/format.dart --check
flutter analyze
flutter test test
```

## Compilar

```sh
flutter build apk --release --flavor production
flutter build appbundle --release --flavor production
```

Configure a assinatura Android antes de distribuir uma versão de release.

## Documentação

- [Testes Android, E2E e ambientes](docs/testing.md)
- [Política de cobertura](docs/test-coverage.md)
- [GitHub Actions, staging e assinatura de release](.github/WORKFLOWS.md)

Consulte o [guia de publicação de APKs nos buckets](docs/apk-publishing.md).
