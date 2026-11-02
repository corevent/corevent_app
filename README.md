# Corevent

Aplicativo Flutter para descobrir eventos, comprar ingressos e gerenciar compras e atividades da conta. Desenvolvido com foco em mobile e arquitetura Feature-first + MVVM.

## Target

- Android.

Nomes exibidos e identificadores Android por flavor:

| Flavor | Nome no Android | Application ID |
| --- | --- | --- |
| `production` | Corevent | `com.corevent.coreventapp` |
| `development` | dev-Corevent | `com.corevent.coreventapp.development` |
| `integration` | dev-Corevent | `com.corevent.coreventapp.integration` |

O prefixo `dev-` identifica as instalações de desenvolvimento/staging e de
integração, tanto em debug quanto em release. O nome é definido pelo flavor;
a API continua sendo selecionada por `COREVENT_API_URL` na compilação. Para staging:

```sh
flutter run --flavor development --dart-define=COREVENT_API_URL=https://corevent-staging-api-666040325433.us-central1.run.app
```

## Pré-requisitos

- Flutter com Dart compatível com `^3.13.4`.
- Android SDK e emulador ou dispositivo físico para Android.

## Como executar

Na raiz do repositório, instale as dependências e gere o código:

```sh
flutter pub get
dart run build_runner build
```

Android:

```sh
flutter devices
flutter run -d ID_DO_DISPOSITIVO
```

Substitua `ID_DO_DISPOSITIVO` pelo identificador listado em `flutter devices`. A API de produção já está configurada no aplicativo.

## Build

Android:

```sh
flutter build apk --release
flutter build appbundle --release
```

Para distribuição, configure a assinatura de release do aplicativo Android.

## Funcionalidades

- Cadastro com verificação de e-mail, login e recuperação de senha.
- Sessão persistente e logout.
- Descoberta de eventos, busca, categorias e prévia dos detalhes.
- Favoritos e avaliações, com edição quando o identificador está disponível.
- Seleção de ingressos, pagamento externo e acompanhamento de pedidos.
- Listagem de ingressos e visualização do QR Code.
- Perfil, edição de dados pessoais, foto e alteração de senha.
- Interface responsiva, fonte ampliada e animações com respeito a movimento reduzido.

## Verificação

```sh
dart tool/format.dart --check
flutter analyze
flutter test
```

Para aplicar a formatação, execute `dart tool/format.dart`.

As metas de cobertura por área estão em [docs/test-coverage.md](docs/test-coverage.md).

### Testes Android

`integration_test/controlled/` usa respostas locais no Dio. Cobre autenticação,
compras, falhas de rede e outros estados determinísticos sem acessar a API.
`test/integration_contracts_test.dart` confere os contratos REST.

```sh
flutter test integration_test/controlled -d ID_DO_DISPOSITIVO --flavor integration
```

`integration_test/e2e/` usa a API real informada por flags. Execute diretamente
com o Flutter em Windows, Linux ou macOS, com um Android conectado e autorizado:

```sh
flutter devices
flutter test integration_test/e2e/all_test.dart -d ID_DO_DISPOSITIVO --flavor integration --dart-define=COREVENT_API_URL=https://URL_DA_API/ --dart-define=COREVENT_E2E_EMAIL=EMAIL --dart-define=COREVENT_E2E_PASSWORD=SENHA --dart-define=COREVENT_E2E_EVENT_ID=ID_RETORNADO --dart-define="COREVENT_E2E_FREE_TICKET_NAME=NOME_RETORNADO"
```

Não há arquivo JSON de configuração nem runner PowerShell para os E2E.
O preparador deve ser executado no projeto da API antes da suíte. Ele garante
a conta E2E, usa essa conta como organizadora e compradora e cria um evento
aberto, pesquisável e avaliável, sem favorito ou
avaliação anteriores da conta, com tipos de ingresso gratuito e pago. Também
deve criar um pedido pago e um ingresso ativo com QR para a conta. O tipo
gratuito deve ter nome único no evento e estoque para novas compras.

O preparador retorna um log estruturado com `eventId` e `freeTicketName`.
Use esses valores nas flags `COREVENT_E2E_EVENT_ID` e
`COREVENT_E2E_FREE_TICKET_NAME`. O mesmo evento atende a busca, favoritos,
avaliação e compra; não são necessários IDs separados. A preparação pertence
à API e ainda não é executada pelo Flutter.

`all_test.dart` é o único arquivo descoberto como teste nessa pasta. Ele reúne
os dez cenários em um build e uma instalação; os arquivos `*_scenarios.dart`
mantêm os cenários separados sem serem executados novamente pela descoberta.
O comando `flutter test integration_test/e2e` também usa esse único entrypoint.

Para executar apenas um grupo, acrescente `--name` ao comando acima:

| Grupo | Comportamento | Filtro |
| --- | --- | --- |
| Somente leitura | Login, abas, sessão, busca, pedidos e QR | `--name "Somente leitura"` |
| Reversíveis | Favorito, avaliação e edição de nome, restaurando o estado | `--name "Reversíveis"` |
| Persistentes | Compra gratuita e upload de foto | `--name "Persistentes"` |

O filtro também aceita o nome de um cenário específico. Os testes validam a
configuração antes das requisições. Os E2E podem gravar dados na API sem uma
flag adicional de autorização. Antes de cada execução completa, o preparador
restaura os dados da conta E2E, limpa os dados anteriores de teste associados
e cria um novo evento, tipos de ingresso, pedido e ingresso com QR. Use os identificadores
retornados nessa execução e uma conta dedicada sem privilégios. As credenciais
passadas ao compilador podem estar presentes no APK de teste.

Pagamento PagBank, cadastro e recuperação por e-mail e restauração após encerrar
o processo são verificações manuais com API real. Para a restauração: faça login,
encerre o app pelo Android, reabra e confirme que a sessão e o perfil retornam;
depois faça logout, reabra e confirme que a sessão permanece encerrada.

O flavor `integration` instala um aplicativo separado, com sufixo
`.integration`, e mantém os dados da instalação normal. Os comandos usuais de
execução e build usam o flavor `production` por padrão.

Os testes limpam apenas as chaves de sessão do aplicativo de integração.

### GitHub Actions

O workflow **Tests** verifica formatação, análise, unitários/widgets/contratos e
integração Android com fixtures em PRs e pushes para `main` e `develop`.
O workflow **Staging E2E** é manual: executa a preparação no GCP, captura os dados
dessa execução e roda a suíte no emulador Android.

Configuração do Environment `staging`, autenticação e relatórios:
[guia de CI](.github/README.md).

O workflow **Development APK** publica um APK debug da `develop`, conectado à
API staging, em uma pré-release no GitHub. O aplicativo usa o sufixo
`.development` para ficar separado da instalação de produção.

O workflow **Release APK** é manual e executa na `main`, usando os quatro secrets
de assinatura do Environment `production`. Informe `build_number` com um código
de versão maior que o anterior. O APK assinado e seu checksum ficam nos
**Artifacts** da execução por 30 dias. A versão exibida vem de `pubspec.yaml`.
