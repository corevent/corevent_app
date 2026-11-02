import base64
from email.parser import BytesParser
import hashlib
import io
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch
from urllib.error import HTTPError

from publish_apk import Storage, command_failure, metadata, publish


class FakeStorage:
    def __init__(self, previous=None, fail=None):
        self.previous = previous
        self.fail = fail
        self.writes = []

    def describe(self, key):
        return {'generation': '17'} if self.previous and key.endswith('latest.json') else None

    def read(self, key, generation):
        assert generation == '17'
        return self.previous

    def put(self, path, key, generation=0, apk=False):
        if self.fail and key.endswith(self.fail):
            raise RuntimeError('Interrupted upload')
        self.writes.append((key, generation, path.read_bytes()))


class PublishApkTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.apk = self.root / 'input.apk'
        self.apk.write_bytes(b'signed apk fixture')
        self.env = {
            'APK_APP': 'app', 'APK_ENVIRONMENT': 'staging',
            'APK_GCP_PROJECT_ID': 'corevent-staging-510316', 'APK_GCS_BUCKET': 'corevent-staging-bucket',
            'GITHUB_ACTIONS': 'true', 'GITHUB_REF': 'refs/heads/develop',
            'GITHUB_REPOSITORY': 'corevent/corevent_app', 'ANDROID_HOME': '/sdk',
            'ANDROID_BUILD_TOOLS': '36.0.0', 'APK_EXPECTED_VERSION_CODE': '42',
            'GITHUB_SHA': 'a' * 40, 'GITHUB_RUN_ID': '123', 'GITHUB_RUN_ATTEMPT': '1',
        }
        self.badging = ("package: name='com.corevent.coreventapp.development' versionCode='42' versionName='1.0.0'\n"
                        "uses-permission: name='android.permission.INTERNET'\n")

    def release(self):
        with patch('publish_apk.execute', side_effect=['Signer #1 certificate DN: CN=Corevent Staging', self.badging]):
            return metadata(self.apk, self.env)

    def test_records_actual_artifact_identity(self):
        release = self.release()
        self.assertEqual(release['sha256'], hashlib.sha256(self.apk.read_bytes()).hexdigest())
        self.assertEqual(release['releaseId'], '1.0.0-42-123-1')
        self.assertEqual(release['apkPath'], 'downloads/app/releases/1.0.0-42-123-1/app.apk')

    def test_rejects_wrong_project_branch_repo_package_version_and_debug_signer(self):
        for key, value in [('APK_GCP_PROJECT_ID', 'corevent'), ('APK_GCS_BUCKET', 'corevent'),
                           ('GITHUB_REF', 'refs/heads/main'), ('GITHUB_REPOSITORY', 'other/repo')]:
            with self.subTest(key=key), patch.dict(self.env, {key: value}):
                with self.assertRaises(ValueError):
                    self.release()
        for badging in [self.badging.replace('.development', ''), self.badging.replace("'42'", "'43'")]:
            with patch('publish_apk.execute', side_effect=['CN=Staging', badging]):
                with self.assertRaises(ValueError):
                    metadata(self.apk, self.env)
        with patch('publish_apk.execute', return_value='Signer #1 certificate DN: CN=Android Debug'):
            with self.assertRaises(ValueError):
                metadata(self.apk, self.env)

    def test_initial_migration_floor_rejects_a_previously_distributed_build(self):
        self.env['APK_MIN_VERSION_CODE'] = '42'
        with self.assertRaises(ValueError):
            self.release()

    def test_work_app_in_production_uses_its_own_package_and_destination(self):
        self.env.update(APK_APP='work', APK_ENVIRONMENT='production',
                        APK_GCP_PROJECT_ID='corevent', APK_GCS_BUCKET='corevent',
                        GITHUB_REF='refs/heads/main', GITHUB_REPOSITORY='corevent/corevent_work_app')
        self.badging = self.badging.replace('com.corevent.coreventapp.development', 'com.corevent.corevent_work_app')
        release = self.release()
        self.assertEqual(release['packageName'], 'com.corevent.corevent_work_app')
        self.assertTrue(release['apkPath'].startswith('downloads/work/releases/'))

    def test_promotes_only_after_all_immutable_files_are_uploaded(self):
        storage = FakeStorage()
        release = self.release()
        self.assertTrue(publish(storage, self.apk, release, self.root / 'output'))
        self.assertEqual(len(storage.writes), 4)
        self.assertTrue(storage.writes[-1][0].endswith('/latest.json'))
        self.assertEqual(storage.writes[-1][1], 0)
        self.assertEqual(json.loads(storage.writes[-1][2]), release)

    def test_upload_failure_never_updates_latest(self):
        storage = FakeStorage(fail='release.json')
        with self.assertRaises(RuntimeError):
            publish(storage, self.apk, self.release(), self.root / 'output')
        self.assertFalse(any(key.endswith('/latest.json') for key, _, _ in storage.writes))

    def test_stale_or_conflicting_version_never_writes(self):
        release = self.release()
        for previous in [dict(release, versionCode=43), dict(release, sha256='b' * 64)]:
            storage = FakeStorage(previous)
            with self.assertRaises(ValueError):
                publish(storage, self.apk, release, self.root / 'output')
            self.assertEqual(storage.writes, [])

    def test_identical_publication_is_idempotent(self):
        release = self.release()
        storage = FakeStorage(release)
        self.assertFalse(publish(storage, self.apk, release, self.root / 'output'))
        self.assertEqual(storage.writes, [])

    def test_existing_pointer_is_updated_with_generation_precondition(self):
        release = self.release()
        storage = FakeStorage(dict(release, versionCode=41))
        publish(storage, self.apk, release, self.root / 'output')
        self.assertEqual(storage.writes[-1][1], '17')


class CommandDiagnosticsTest(unittest.TestCase):
    def test_signature_stdout_is_reported_but_token_command_stdout_is_never_reported(self):
        error = subprocess.CalledProcessError(1, ['apksigner', 'verify', '/private/app.apk'],
                                              output='APK signature verification failed')
        self.assertIn('APK signature verification failed', command_failure(error))
        error = subprocess.CalledProcessError(1, ['gcloud', 'auth', 'print-access-token'],
                                              output='opaque-secret-token')
        self.assertNotIn('opaque-secret-token', command_failure(error))

    def test_reports_failing_subcommand_and_permission_without_command_arguments(self):
        error = subprocess.CalledProcessError(
            1, ['gcloud', 'storage', 'objects', 'describe', 'private-file'],
            stderr='PERMISSION_DENIED: missing storage.objects.create')
        message = command_failure(error)
        self.assertIn('gcloud storage objects describe (exit 1)', message)
        self.assertIn('storage.objects.create', message)
        self.assertNotIn('private-file', message)

    def test_redacts_tokens_signed_urls_and_private_keys(self):
        error = subprocess.CalledProcessError(
            1, ['/sdk/apksigner', 'verify', '/private/artifact.apk'],
            stderr=('https://example.com/file?X-Goog-Signature=signed-secret\n'
                    'Authorization: Bearer bearer-secret\n'
                    '{"access_token":"access-secret","client_secret":"client-secret"}\n'
                    '-----BEGIN PRIVATE KEY-----\nkey-secret\n-----END PRIVATE KEY-----\n'
                    'eyJheader.payload.signature ya29.token-secret\n'
                    '::error::diagnostic'))
        message = command_failure(error)
        for secret in ['signed-secret', 'bearer-secret', 'access-secret', 'client-secret',
                       'key-secret', 'eyJheader.payload.signature', 'ya29.token-secret']:
            self.assertNotIn(secret, message)
        self.assertIn('apksigner verify (exit 1)', message)
        self.assertIn('\n  : :error: :diagnostic', message)

    def test_missing_manifest_is_allowed_but_permission_denied_is_not(self):
        storage = Storage('project', 'bucket')
        missing = subprocess.CalledProcessError(1, ['gcloud'], stderr='object not found: 404.')
        with patch('publish_apk.execute', side_effect=missing):
            self.assertIsNone(storage.describe('downloads/work/latest.json'))
        denied = subprocess.CalledProcessError(1, ['gcloud'], stderr='PERMISSION_DENIED')
        with patch('publish_apk.execute', side_effect=denied):
            with self.assertRaises(subprocess.CalledProcessError):
                storage.describe('downloads/work/latest.json')


class StorageUploadTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.path = Path(self.temp.name) / 'input.apk'
        self.data = b'signed apk fixture\x00\xff'
        self.path.write_bytes(self.data)
        self.md5 = base64.b64encode(hashlib.md5(self.data).digest()).decode()
        self.storage = Storage('project', 'bucket')

    def test_direct_upload_needs_no_list_and_preserves_bytes_metadata_and_precondition(self):
        for generation in (0, 17):
            with self.subTest(generation=generation):
                self.storage._token = None
                descriptions = ([None] if generation == 0 else []) + [{'md5_hash': self.md5}]
                with patch.object(self.storage, 'describe', side_effect=descriptions), \
                     patch('publish_apk.execute', return_value='temporary-token\n') as execute, \
                     patch('publish_apk.urlopen', return_value=io.BytesIO(b'{}')) as upload:
                    self.storage.put(self.path, 'downloads/work/releases/42/app.apk', generation, apk=True)
                execute.assert_called_once_with(['gcloud', 'auth', 'print-access-token',
                                                 '--project', 'project', '--quiet'])
                request = upload.call_args.args[0]
                self.assertEqual(request.method, 'POST')
                self.assertIn('uploadType=multipart', request.full_url)
                self.assertIn(f'ifGenerationMatch={generation}', request.full_url)
                self.assertEqual(request.get_header('Authorization'), 'Bearer temporary-token')
                message = BytesParser().parsebytes(
                    ('Content-Type: ' + request.get_header('Content-type') + '\r\n\r\n').encode()
                    + request.data)
                meta_part, media_part = message.get_payload()
                metadata = json.loads(meta_part.get_payload(decode=True))
                self.assertEqual(metadata['name'], 'downloads/work/releases/42/app.apk')
                self.assertEqual(metadata['md5Hash'], self.md5)
                self.assertEqual(metadata['metadata']['sha256'], hashlib.sha256(self.data).hexdigest())
                self.assertEqual(metadata['cacheControl'], 'private,max-age=31536000')
                self.assertIn('attachment', metadata['contentDisposition'])
                self.assertEqual(media_part.get_payload(decode=True), self.data)

    def test_existing_immutable_object_is_idempotent_or_rejected_without_upload(self):
        for md5 in (self.md5, 'different'):
            with patch.object(self.storage, 'describe', return_value={'md5_hash': md5}), \
                 patch('publish_apk.urlopen') as upload:
                if md5 == self.md5:
                    self.storage.put(self.path, 'downloads/work/releases/42/app.apk')
                else:
                    with self.assertRaisesRegex(ValueError, 'different content'):
                        self.storage.put(self.path, 'downloads/work/releases/42/app.apk')
                upload.assert_not_called()

    def test_precondition_failure_keeps_http_diagnostic_and_redacts_credentials(self):
        error = HTTPError('https://storage.googleapis.com', 412, 'Precondition Failed', {},
                          io.BytesIO(b'{"message":"generation mismatch", "access_token":"secret-value"}'))
        with patch.object(self.storage, 'describe', return_value=None), \
             patch('publish_apk.execute', return_value='temporary-token'), \
             patch('publish_apk.urlopen', side_effect=error):
            with self.assertRaises(ValueError) as raised:
                self.storage.put(self.path, 'downloads/work/latest.json', generation='17')
        self.assertIn('HTTP 412', str(raised.exception))
        self.assertIn('generation mismatch', str(raised.exception))
        self.assertNotIn('secret-value', str(raised.exception))

    def test_uploaded_checksum_must_match(self):
        with patch.object(self.storage, 'describe', side_effect=[None, {'md5_hash': 'different'}]), \
             patch('publish_apk.execute', return_value='temporary-token'), \
             patch('publish_apk.urlopen', return_value=io.BytesIO(b'{}')):
            with self.assertRaisesRegex(ValueError, 'checksum mismatch'):
                self.storage.put(self.path, 'downloads/work/latest.json')


if __name__ == '__main__':
    unittest.main()
