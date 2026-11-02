import hashlib
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from publish_apk import metadata, publish


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


if __name__ == '__main__':
    unittest.main()
