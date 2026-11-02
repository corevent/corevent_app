# Publicação de APKs nos buckets

## Destinos

| Ambiente | Projeto | Bucket | Prefixo deste app |
| --- | --- | --- | --- |
| Staging | corevent-staging-510316 | corevent-staging-bucket | downloads/app/ |
| Produção | corevent | corevent | downloads/app/ |

`Development APK` executa em push ou disparo manual na `develop`, usando o
Environment `staging`. Compila `--release --flavor development`, com chave fixa
exclusiva de staging e API definida por `COREVENT_API_URL`.
`Release APK` permanece manual na `main`, com Environment `production`, variante
`production`, chave de produção e build_number informado pelo operador.
Ambos usam Flutter 3.47.5, Java 17, Ubuntu 24.04 e preparação do NDK com até três
tentativas de instalação.

## Configuração no GitHub

Cada Environment precisa destas variáveis:

- `APK_GCP_PROJECT_ID`: projeto da tabela acima.
- `APK_GCS_BUCKET`: bucket da tabela acima.
- `APK_GCP_WIF_PROVIDER`: provider do pool `github-apk` no respectivo projeto.
- `APK_GCP_SERVICE_ACCOUNT`: conta `github-apk-app@PROJETO.iam.gserviceaccount.com`.
- `APK_MIN_VERSION_CODE`: limite inicial de migração; novos builds devem ser maiores.

Staging também usa `COREVENT_API_URL`, com a URL HTTPS da API de testes.
As variáveis APK são independentes da autenticação de testes E2E.

Os dois Environments usam estes secrets, cada ambiente com sua chave própria:
`ANDROID_KEYSTORE_BASE64`, `ANDROID_STORE_PASSWORD`, `ANDROID_KEY_ALIAS` e
`ANDROID_KEY_PASSWORD`. Não copie a chave de produção para staging.

A autenticação usa Workload Identity Federation e uma conta publicadora por app,
com acesso restrito ao seu prefixo no bucket. Preserve as chaves já cadastradas.
Nenhum arquivo de chave ou credencial de nuvem deve ser commitado.
Os APKs antigos de staging tinham assinatura de debug; na primeira migração para
a chave fixa será necessário desinstalar essa instalação antiga. Após a migração,
novas versões com versionCode maior usam a mesma chave e permitem atualização.

## Arquivos publicados

```text
downloads/app/
  latest.json
  releases/<versionName>-<versionCode>-<runId>-<runAttempt>/
    app.apk
    app.apk.sha256
    release.json
```

O publicador verifica assinatura release, pacote Android, INTERNET, versão,
repositório, branch e destino. Cada upload é conferido pelo checksum MD5 do
Cloud Storage; SHA-256 é registrado no manifesto e nos metadados.
A indicação `latest.json` só é alterada após os três arquivos versionados serem
confirmados. O update usa a geração anterior como precondição para evitar
sobrescrita concorrente. Builds mais antigos não podem se tornar a versão atual.

Os objetos são privados. O APK pode usar cache longo por ter caminho imutável;
manifestos e checksums usam `no-store`. O download privado pode ser feito
pelo console do Cloud Storage ou por `gcloud storage cp`. A página de downloads
e os endpoints na API não fazem parte desta implementação.

Os arquivos continuam sendo publicados nas pré-releases de staging e nos
artefatos de produção do GitHub, além do bucket. Falha no upload impede avançar
para a publicação no GitHub; falha posterior no GitHub não desfaz um upload já
confirmado. Uma nova execução deve usar versionCode maior caso o APK seja outro.

## Testes e operação

```sh
python -m unittest discover -s .github/scripts -p 'test_*.py'
bash -n .github/scripts/prepare_android_sdk.sh
```

Esses testes usam dados fictícios e não fazem uploads reais. Testam destino,
identidade do APK, ordem dos uploads, interrupções, proteção contra regressão,
idempotência e promoção condicionada à geração.

A primeira publicação de produção deve usar build_number maior que 2 e que
qualquer build distribuído posteriormente. As chaves de produção existentes são
preservadas. A página de downloads fica para uma etapa posterior.

## Diagnóstico de falhas

Os builds release permitem que o Flutter regenere o registro de plugins,
excluindo dependências de teste como `integration_test`. Não use `--no-pub`
ao alternar de testes/debug para release.

O publicador informa a fase atual e, em caso de erro, a ferramenta/subcomando,
o código de saída e o diagnóstico com tokens, chaves e URLs HTTP removidos.
Uma falha na configuração da autenticação pode aparecer apenas no primeiro
acesso ao Storage; a etapa de autenticação passar não comprova o upload.
