"""Validate and publish an immutable APK release, then advance its private manifest."""

import base64
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys


TARGETS = {
    'staging': ('corevent-staging-510316', 'corevent-staging-bucket'),
    'production': ('corevent', 'corevent'),
}
PACKAGES = {'app': 'com.corevent.coreventapp', 'work': 'com.corevent.corevent_work_app'}


def execute(arguments):
    return subprocess.run(arguments, check=True, text=True, capture_output=True, timeout=300).stdout


class Storage:
    def __init__(self, project, bucket):
        self.project = project
        self.bucket = bucket

    def uri(self, key):
        return f'gs://{self.bucket}/{key}'

    def describe(self, key):
        try:
            return json.loads(execute(['gcloud', 'storage', 'objects', 'describe', self.uri(key),
                                       '--format=json', '--project', self.project, '--quiet']))
        except subprocess.CalledProcessError as error:
            if re.search(r'\b404\b|NotFound|not found|No URLs matched', error.stderr or '', re.I):
                return None
            raise

    def read(self, key, generation):
        return json.loads(execute(['gcloud', 'storage', 'cat', self.uri(key) + '#' + str(generation),
                                  '--project', self.project, '--quiet']))

    def put(self, path, key, generation=0, apk=False):
        data = path.read_bytes()
        digest = hashlib.sha256(data).hexdigest()
        existing = self.describe(key) if generation == 0 else None
        expected_md5 = base64.b64encode(hashlib.md5(data).digest()).decode()
        if existing:
            if existing.get('md5_hash', existing.get('md5Hash')) == expected_md5:
                return
            raise ValueError('An immutable release object already exists with different content')
        command = ['gcloud', 'storage', 'cp', str(path), self.uri(key), '--project', self.project,
                   '--if-generation-match=' + str(generation), '--quiet',
                   '--cache-control=' + ('private,max-age=31536000' if apk else 'no-store'),
                   '--content-type=' + ('application/vnd.android.package-archive' if apk else
                                        'text/plain' if path.suffix == '.sha256' else 'application/json'),
                   '--custom-metadata=sha256=' + digest]
        if apk:
            command.append('--content-disposition=attachment; filename="corevent.apk"')
        execute(command)
        uploaded = self.describe(key)
        if not uploaded or uploaded.get('md5_hash', uploaded.get('md5Hash')) != expected_md5:
            raise ValueError('Uploaded object checksum mismatch')


def publish(storage, apk, release, output):
    prefix = f"downloads/{release['app']}"
    latest_key = prefix + '/latest.json'
    current = storage.describe(latest_key)
    generation = current['generation'] if current else 0
    if current:
        previous = storage.read(latest_key, generation)
        if previous.get('app') != release['app'] or previous.get('environment') != release['environment']:
            raise ValueError('Existing manifest belongs to another target')
        previous_code = previous.get('versionCode')
        if not isinstance(previous_code, int):
            raise ValueError('Invalid existing versionCode')
        if previous_code >= release['versionCode']:
            if previous_code == release['versionCode'] and previous.get('sha256') == release['sha256']:
                return False
            raise ValueError('versionCode must be greater than the latest published build')
    output.mkdir(parents=True, exist_ok=True)
    manifest = output / 'release.json'
    manifest.write_text(json.dumps(release, indent=2) + '\n', encoding='utf-8')
    checksum = output / 'app.apk.sha256'
    checksum.write_text(release['sha256'] + '  app.apk\n', encoding='ascii')
    release_prefix = release['apkPath'].rsplit('/', 1)[0]
    storage.put(apk, release['apkPath'], apk=True)
    storage.put(checksum, release_prefix + '/app.apk.sha256')
    storage.put(manifest, release_prefix + '/release.json')
    # Compare-and-swap: a concurrent publisher cannot silently replace this pointer.
    storage.put(manifest, latest_key, generation=generation)
    return True


def metadata(apk, env):
    app = env['APK_APP']
    environment = env['APK_ENVIRONMENT']
    if app not in PACKAGES or environment not in TARGETS:
        raise ValueError('Invalid publication target')
    project, bucket = TARGETS[environment]
    if env['APK_GCP_PROJECT_ID'] != project or env['APK_GCS_BUCKET'] != bucket:
        raise ValueError('Project/bucket does not match the selected environment')
    expected_ref = 'refs/heads/develop' if environment == 'staging' else 'refs/heads/main'
    expected_repo = 'corevent/corevent_app' if app == 'app' else 'corevent/corevent_work_app'
    if env.get('GITHUB_ACTIONS') != 'true' or env['GITHUB_REF'] != expected_ref or env['GITHUB_REPOSITORY'] != expected_repo:
        raise ValueError('Unexpected GitHub repository or branch')
    tools = Path(env['ANDROID_HOME']) / 'build-tools' / env['ANDROID_BUILD_TOOLS']
    signature = execute([str(tools / 'apksigner'), 'verify', '--verbose', '--print-certs', str(apk)])
    if 'CN=Android Debug' in signature:
        raise ValueError('Distribution requires a stable release signing key')
    badging = execute([str(tools / 'aapt'), 'dump', 'badging', str(apk)])
    package = re.search(r"^package: name='([^']+)' versionCode='(\d+)' versionName='([^']+)'", badging, re.M)
    expected_package = PACKAGES[app] + ('.development' if environment == 'staging' else '')
    if not package or package[1] != expected_package or int(package[2]) != int(env['APK_EXPECTED_VERSION_CODE']):
        raise ValueError('Unexpected APK package or versionCode')
    if not re.search(r"uses-permission: name='android.permission.INTERNET'", badging):
        raise ValueError('APK is missing INTERNET permission')
    version = package[3]
    code = int(package[2])
    minimum = int(env.get('APK_MIN_VERSION_CODE', '0'))
    if not re.fullmatch(r'\d+\.\d+\.\d+(?:[.-][a-zA-Z0-9]+)*', version) or not minimum < code <= 2100000000:
        raise ValueError('Invalid Android version')
    if not re.fullmatch(r'[a-f0-9]{40}', env['GITHUB_SHA']) or not re.fullmatch(r'\d+', env['GITHUB_RUN_ID']):
        raise ValueError('Invalid GitHub build identity')
    attempt = int(env['GITHUB_RUN_ATTEMPT'])
    if attempt <= 0:
        raise ValueError('Invalid run attempt')
    release_id = f"{version}-{code}-{env['GITHUB_RUN_ID']}-{attempt}"
    data = apk.read_bytes()
    if not data:
        raise ValueError('Empty APK')
    return {
        'schemaVersion': 1, 'app': app, 'environment': environment, 'packageName': expected_package,
        'versionName': version, 'versionCode': code, 'releaseId': release_id,
        'commit': env['GITHUB_SHA'], 'runId': env['GITHUB_RUN_ID'], 'runAttempt': attempt,
        'publishedAt': datetime.now(timezone.utc).isoformat(timespec='seconds').replace('+00:00', 'Z'),
        'apkPath': f'downloads/{app}/releases/{release_id}/app.apk',
        'sizeBytes': len(data), 'sha256': hashlib.sha256(data).hexdigest(),
    }


def main():
    apk = Path(os.environ['APK_FILE'])
    release = metadata(apk, os.environ)
    changed = publish(Storage(os.environ['APK_GCP_PROJECT_ID'], os.environ['APK_GCS_BUCKET']),
                      apk, release, Path('dist/publication'))
    print(json.dumps({'published': changed, 'app': release['app'],
                      'environment': release['environment'], 'versionCode': release['versionCode']}))


if __name__ == '__main__':
    try:
        main()
    except subprocess.CalledProcessError as error:
        # Authentication material and signed URLs must not be printed.
        print(f'APK publication command failed (exit {error.returncode}).', file=sys.stderr)
        sys.exit(1)
    except (ValueError, KeyError, OSError, subprocess.TimeoutExpired) as error:
        print(f'APK publication failed: {error}', file=sys.stderr)
        sys.exit(1)
