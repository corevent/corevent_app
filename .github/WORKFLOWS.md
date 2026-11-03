> Publicação nos buckets e assinatura de staging: [guia de APKs](../docs/apk-publishing.md).

# GitHub Actions

## Workflows

- **Development APK** (`workflows/development-apk.yml`): runs on pushes to
  `develop` and manual dispatch on that branch. Generates code, runs analysis
  and unit/widget tests, builds a signed release APK with the `development` flavor,
  then publishes a GitHub pre-release with the APK and its SHA-256 checksum.
  It uses `COREVENT_API_URL` from the `staging` Environment and uses staging signing secrets and GCP Workload Identity Federation. The `.development` application ID
  keeps its installation and session separate from production and integration.
  Each run creates a `dev-RUN-ATTEMPT` tag; production releases remain unchanged.
  Download `corevent-development.apk` from **Releases**. Android integration
  remains in the Tests workflow; this publication does not wait for that workflow.
  Staging uses a fixed signing key configured in its Environment. Migrating from
  a previous debug-signed APK requires reinstalling once.
- **Release APK** (`workflows/release-apk.yml`): manual dispatch on `main`, using
  the `production` Environment. Checks formatting, generated code, analysis,
  unit/widget/contract tests and CI helpers. Builds a universal production APK
  with the configured release key and the supplied Android versionCode.
  Verifies the signature, application ID, versionCode and INTERNET permission,
  then uploads the APK, SHA-256 checksum and public signature/build metadata
  as an Actions artifact for 30 days. GCP authentication publishes the same APK to its private bucket. No emulator or API preparation is used.
  Signing files are temporary and removed even on failure.
- **Tests** (`workflows/tests.yml`): runs on pull requests, pushes to `main` or
  `develop`, and manual dispatch. Checks formatting, generation, analysis, unit,
  widget and contract tests, then Android integration with fixtures. No API or
  Google Cloud credentials are required. Flutter 3.47.5, Java 17 and an Android
  API 33 x86_64 emulator are used.
- **Staging E2E** (`workflows/e2e.yml`): manual dispatch in GitHub Actions. Runs
  the existing preparation Job, reads its structured result, then executes the
  ten E2E scenarios on one emulator through `integration_test/e2e/all_test.dart`.
  The workflow changes data in staging and serializes preparation plus tests.

The E2E workflow requires `.github/workflows/e2e.yml` on the repository's default
branch for its manual dispatch entry to appear in Actions. Configure the
`staging` Environment to allow only trusted branches such as `main` and `develop`.
Preparation must not be launched manually or by another repository while this
suite is running: GitHub concurrency protects only workflows in this repository.

## GitHub configuration

Android integration and E2E pin their runner to `ubuntu-24.04` and share
`scripts/enable-kvm.sh`. The setup keeps the udev rule, waits briefly for udev,
sets device permissions explicitly and retries availability/permissions up to
10 times. Image version, kernel, user and KVM permissions are recorded in
`reports/kvm-setup.log`, included in each workflow's result artifact even when
setup fails. Pinning the OS version still allows updates to that runner image;
it does not guarantee virtualization availability on every machine.

In **Settings → Environments → staging**, add:

| Type | Name | Value |
| --- | --- | --- |
| Variable | `GCP_PROJECT_ID` | `corevent-staging-510316` |
| Variable | `GCP_REGION` | `us-central1` |
| Variable | `GCP_PREPARE_JOB` | Existing Cloud Run preparation Job name |
| Variable | `COREVENT_API_URL` | `https://corevent-staging-api-666040325433.us-central1.run.app` |
| Variable | `GCP_WIF_PROVIDER` | `projects/NUMBER/locations/global/workloadIdentityPools/POOL/providers/PROVIDER` |
| Variable | `GCP_SERVICE_ACCOUNT` | Service account email for GitHub Actions |
| Secret | `COREVENT_E2E_EMAIL` | Email of the account created by the preparator |
| Secret | `COREVENT_E2E_PASSWORD` | Password of that account |

`eventId` and `freeTicketName` are read automatically from the preparation JSON.
The generated `reports/preparation.json` is an output artifact, not an E2E input
configuration file. No API keys, database passwords or QR secrets are stored in
GitHub by these workflows.

## Production release configuration

Add these **secrets** in **Settings → Environments → production**:

| Name | Value |
| --- | --- |
| `ANDROID_KEYSTORE_BASE64` | Base64-encoded release keystore contents |
| `ANDROID_STORE_PASSWORD` | Keystore password |
| `ANDROID_KEY_ALIAS` | Key alias in that keystore |
| `ANDROID_KEY_PASSWORD` | Password for that key |

Allow the `main` branch in that Environment. Merge the workflow into the default
branch before looking for its **Run workflow** button. Select **Release APK →
Run workflow → main**, then enter `build_number`: a positive Android versionCode
greater than the previous released version, up to 2100000000. The versionName
comes from `pubspec.yaml`. The workflow validates the range, but does not query
Google Play or previous artifacts to determine the next versionCode.

Alternatively:

```sh
gh workflow run release-apk.yml --ref main -f build_number=2
```

Download `production-apk-BUILD_NUMBER` from the run's **Artifacts**. This workflow
builds a signed APK; it does not publish to Google Play or create a GitHub Release.
The production API URL already configured in the app is used.

The helper escapes passwords for Java Properties, rejects missing secrets or
invalid Base64, and writes private files. Only APK/checksum/public metadata files
are uploaded; never upload `android/key.properties` or the keystore.

Before compiling the APK, keytool generates a temporary certificate request to
verify that the configured alias is a private key and both passwords can recover
it. This request is removed with the signing files and is never uploaded. If the
alias is missing, update `ANDROID_KEY_ALIAS` from the local `keyAlias` and encode
the exact keystore referenced by local `storeFile` again. All four secrets must
describe the same key; files created under different names can contain different
aliases. The preflight uses password environment variables and suppresses keytool
output so credentials are not included in logs.

## Google Cloud configuration

Configure [Workload Identity Federation](https://github.com/google-github-actions/auth)
for GitHub's OIDC provider. Restrict the provider to this repository and trusted
refs/environment. Grant its matching principal `roles/iam.workloadIdentityUser`
on the GitHub service account so it can impersonate that account.

The GitHub service account needs:

- `roles/run.invoker` on the preparation Job to execute it.
- `roles/logging.viewer` on the staging project to read the result logs.

The preparation Job itself uses its own runtime service account and existing
database/Secret Manager/network permissions. It must use the updated API image,
command `node`, argument `dist/database/seeds/prepare-e2e.js`, `NODE_ENV=staging`,
one task, parallelism one and zero automatic retries. Its database and
`QR_CODE_SECRET` must match the staging API.

The workflow does not deploy the API, run migrations or modify the Job's
configuration. Ensure those are current before dispatching the suite.

## Results and failure behavior

Artifacts are uploaded even after failure:

- Unit: LCOV, readable log and JSON-lines test results; retained for 14 days.
- Android integration: readable log, JSON-lines results, logcat and command
  duration/exit code; retained for 14 days.
- E2E: the same Android reports plus preparation identifiers/result; retained
  for 7 days. APKs and authentication files are not uploaded.

Flutter failures preserve the failing exit code. Preparation failure, an invalid
schema, account mismatch or ambiguous output prevents E2E execution. Logs are
filtered by the exact execution name returned by `gcloud`, not the latest Job
execution. The reader tolerates log-ingestion delay for up to 120 seconds without
starting another preparation.

The photo scenario remains enabled and can fail until its initial avatar URL is
fixed. External payment, email and process-restart scenarios remain manual.
Coverage thresholds are enforced by `dart tool/check_coverage.dart` in Tests and
Release APK. Both workflows publish an automatic Markdown/JSON report and LCOV
artifact. See [coverage policy](../docs/test-coverage.md); generated metrics are
not committed to Git.

After the first successful CI run, require the **Unit, widget and contract tests**
and **Android integration with fixtures** checks in branch protection. The
manually dispatched E2E workflow should not be a required check on every PR.

## Local checks for CI helpers

```sh
python -m unittest discover -s .github/scripts -p 'test_*.py'
bash -n .github/scripts/run-android-tests.sh
```

These checks neither execute the Cloud Run Job nor contact the API. To run the
Android suites locally, see the [testing guide](../docs/testing.md).
