# Testes e ambientes Android

Execute os comandos deste guia na raiz do repositório.

## Ambientes

| Flavor | Nome no Android | Application ID |
| --- | --- | --- |
| `production` | Corevent | `com.corevent.coreventapp` |
| `development` | dev-Corevent | `com.corevent.coreventapp.development` |
| `integration` | dev-Corevent | `com.corevent.coreventapp.integration` |

O prefixo `dev-` identifica as instalações de desenvolvimento/staging e de
integração, tanto em debug quanto em release. O nome é definido pelo flavor;
a API é selecionada por `COREVENT_API_URL` na compilação. Sem essa flag,
a URL padrão de produção é usada. Informe a API de staging ao executar os E2E.

## Verificações locais

```sh
dart tool/format.dart --check
flutter analyze
flutter test test
```

Para aplicar a formatação, execute `dart tool/format.dart`.
As metas e os comandos de cobertura estão na [política de cobertura](test-coverage.md).

## Integração Android

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

## GitHub Actions

Os workflows de testes, E2E de staging e geração de APK estão documentados no
[guia de GitHub Actions](../.github/WORKFLOWS.md).
