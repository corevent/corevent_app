#!/usr/bin/env bash
set -euo pipefail
sdkmanager="$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager"
ndk_version=28.2.13676358
for attempt in 1 2 3; do
  if "$sdkmanager" "build-tools;${ANDROID_BUILD_TOOLS:?}" "ndk;$ndk_version"; then
    test -f "$ANDROID_HOME/ndk/$ndk_version/source.properties"
    exit 0
  fi
  if [[ "$attempt" == 3 ]]; then
    echo '::error::Android SDK/NDK installation failed after three attempts'
    exit 1
  fi
  "$sdkmanager" --uninstall "ndk;$ndk_version" || true
  sleep "$((attempt * 3))"
done
