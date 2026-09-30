#!/usr/bin/env bash
# Configures the generated Flutter Android runner for the Capsi release build.
#
# `flutter create` writes a template runner that is not fit for a release build
# of this application: the INTERNET permission only lands in the debug and
# profile manifests, the application id is still the template placeholder, and
# the label is the raw project name. Capsi is a peer-to-peer LAN messenger, so
# a release build without INTERNET cannot open a single socket.
#
# The script is idempotent and is safe to run after every `flutter create`.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

APPLICATION_ID="win.capsi.app"
APP_LABEL="Capsi"
GRADLE="android/app/build.gradle.kts"
MANIFEST="android/app/src/main/AndroidManifest.xml"

if [ ! -f "$GRADLE" ]; then
  echo "Android runner is missing: $GRADLE. Run tool/bootstrap_platforms.sh first." >&2
  exit 1
fi
if [ ! -f "$MANIFEST" ]; then
  echo "Android manifest is missing: $MANIFEST. Run tool/bootstrap_platforms.sh first." >&2
  exit 1
fi

sed -i -E "s|^([[:space:]]*)namespace[[:space:]]*=[[:space:]]*\"[^\"]+\"|\1namespace = \"$APPLICATION_ID\"|" "$GRADLE"
sed -i -E "s|^([[:space:]]*)applicationId[[:space:]]*=[[:space:]]*\"[^\"]+\"|\1applicationId = \"$APPLICATION_ID\"|" "$GRADLE"
echo "Android application id set to $APPLICATION_ID."

# The manifest names the activity ".MainActivity", which the manifest merger
# resolves against the namespace, so the class must live in the application id's
# package. `flutter create` put it in the template's com.example.capsi, which
# would compile happily and then die with "unable to find explicit activity
# class" the moment anyone tapped the icon.
KOTLIN="android/app/src/main/kotlin"
MAIN_ACTIVITY="$KOTLIN/${APPLICATION_ID//.//}/MainActivity.kt"
mkdir -p "$(dirname "$MAIN_ACTIVITY")"
MISPLACED=$(find "$KOTLIN" -name MainActivity.kt ! -path "$MAIN_ACTIVITY")
if [ -n "$MISPLACED" ]; then
  first=$(printf '%s\n' "$MISPLACED" | head -n 1)
  sed -E "s|^package[[:space:]]+[A-Za-z0-9_.]+|package $APPLICATION_ID|" "$first" > "$MAIN_ACTIVITY"
  # shellcheck disable=SC2086
  rm -f $MISPLACED
  # shellcheck disable=SC2086
  for stale in $MISPLACED; do find "$KOTLIN" -type d -empty -delete; done
  echo "MainActivity.kt moved into the $APPLICATION_ID package."
elif [ ! -f "$MAIN_ACTIVITY" ]; then
  printf 'package %s\n\nimport io.flutter.embedding.android.FlutterActivity\n\nclass MainActivity : FlutterActivity()\n' "$APPLICATION_ID" > "$MAIN_ACTIVITY"
  echo "Created MainActivity.kt in the $APPLICATION_ID package."
else
  echo "MainActivity.kt is already in the $APPLICATION_ID package."
fi

sed -i -E "s|android:label=\"[^\"]*\"|android:label=\"$APP_LABEL\"|" "$MANIFEST"
if ! grep -q 'android\.permission\.INTERNET' "$MANIFEST"; then
  perl -0pi -e 's{^(<manifest[^>]*>)}{$1
    <!-- Capsi talks to peers on the local network in every build, so the
         permission belongs in the main manifest, not only in debug. -->
    <uses-permission android:name="android.permission.INTERNET"/>
    <uses-permission android:name="android.permission.ACCESS_NETWORK_STATE"/>}' "$MANIFEST"
  echo "Added the INTERNET permission to the main manifest."
else
  echo "The INTERNET permission is already declared."
fi

# The Flutter template asks for `-Xmx8G`. That is more heap than a typical Capsi
# development or CI box has memory for: the Gradle daemon reserves it, the Kotlin
# compile daemon and the AGP build-logic process ask for their own on top, and
# the resulting page-file thrash stalls a JVM long enough for Gradle's 60-second
# internal file-lock timeout to fire mid-build ("Timeout waiting to lock build
# logic queue"). Keep one JVM, keep it inside physical memory.
PROPERTIES="android/gradle.properties"
set_property() {
  local key="$1" value="$2"
  if grep -qE "^${key}[[:space:]]*=" "$PROPERTIES"; then
    sed -i -E "s|^${key}[[:space:]]*=.*|${key}=${value}|" "$PROPERTIES"
  else
    printf '%s=%s\n' "$key" "$value" >> "$PROPERTIES"
  fi
}
set_property "org.gradle.jvmargs" "-Xmx2048m -XX:MaxMetaspaceSize=768m -XX:ReservedCodeCacheSize=256m"
set_property "kotlin.compiler.execution.strategy" "in-process"
set_property "org.gradle.workers.max" "2"
echo "Gradle heap and worker limits sized for a release build on a modest box."

echo "Capsi Android runner configured."
