"""Prepare temporary Android signing files for the release workflow."""

import base64
import binascii
import os
from pathlib import Path
import sys

SECRET_NAMES = (
    "ANDROID_KEYSTORE_BASE64",
    "ANDROID_STORE_PASSWORD",
    "ANDROID_KEY_ALIAS",
    "ANDROID_KEY_PASSWORD",
)


def escape_property(value):
    """Preserve secrets literally in Java Properties, including whitespace."""
    return value.translate(str.maketrans({
        "\\": "\\\\", "\n": "\\n", "\r": "\\r", "\t": "\\t", "\f": "\\f",
        "=": "\\=", ":": "\\:", "#": "\\#", "!": "\\!", " ": "\\ ",
    }))


def write_private(path, content):
    descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(descriptor, "wb") as output:
        os.chmod(path, 0o600)
        output.write(content)


def prepare_signing(workspace, temporary, secrets):
    missing = [name for name in SECRET_NAMES if not secrets.get(name, "").strip()]
    if missing:
        raise ValueError("Missing Android signing secrets: " + ", ".join(missing))

    encoded = "".join(secrets["ANDROID_KEYSTORE_BASE64"].split())
    try:
        keystore = base64.b64decode(encoded, validate=True)
    except (binascii.Error, ValueError):
        raise ValueError("ANDROID_KEYSTORE_BASE64 must contain valid Base64.") from None
    if not keystore:
        raise ValueError("ANDROID_KEYSTORE_BASE64 decoded to an empty keystore.")

    keystore_path = temporary / "android-release-keystore.jks"
    properties_path = workspace / "android" / "key.properties"
    properties = {
        "storeFile": str(keystore_path.resolve()),
        "storePassword": secrets["ANDROID_STORE_PASSWORD"],
        "keyAlias": secrets["ANDROID_KEY_ALIAS"],
        "keyPassword": secrets["ANDROID_KEY_PASSWORD"],
    }
    content = "".join(
        f"{key}={escape_property(value)}\n" for key, value in properties.items()
    )
    write_private(keystore_path, keystore)
    write_private(properties_path, content.encode("utf-8"))
    return keystore_path, properties_path


def main():
    if os.environ.get("GITHUB_ACTIONS") != "true":
        raise ValueError("This helper is intended for GitHub Actions.")
    prepare_signing(
        Path(os.environ["GITHUB_WORKSPACE"]),
        Path(os.environ["RUNNER_TEMP"]),
        os.environ,
    )


if __name__ == "__main__":
    try:
        main()
    except (ValueError, KeyError, OSError) as error:
        print(f"Signing preparation failed: {error}", file=sys.stderr)
        sys.exit(1)

