#!/usr/bin/env bash
# Rebuilds build/PoliceChaseVR.apk on Linux x86_64 from a clean checkout.
# Downloads Godot 4.5.2, its export templates, JDK 17 and the Android SDK into
# ~/.cache/policechase-build (about 3 GB) the first time it runs.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CACHE="${CACHE:-$HOME/.cache/policechase-build}"
GODOT_VER="4.5.2"
GODOT="$CACHE/godot/Godot_v${GODOT_VER}-stable_linux.x86_64"
SDK="$CACHE/android-sdk"
JDK="$CACHE/jdk17"
TPL="$HOME/.local/share/godot/export_templates/${GODOT_VER}.stable"
mkdir -p "$CACHE"
fetch() { [ -f "$2" ] || curl -fL --retry 3 -o "$2.part" "$1" && { [ -f "$2" ] || mv "$2.part" "$2"; }; }

# 1. Godot editor + export templates
if [ ! -x "$GODOT" ]; then
  fetch "https://github.com/godotengine/godot/releases/download/${GODOT_VER}-stable/Godot_v${GODOT_VER}-stable_linux.x86_64.zip" "$CACHE/godot.zip"
  unzip -q -o "$CACHE/godot.zip" -d "$CACHE/godot"
fi
if [ ! -f "$TPL/android_source.zip" ]; then
  fetch "https://github.com/godotengine/godot/releases/download/${GODOT_VER}-stable/Godot_v${GODOT_VER}-stable_export_templates.tpz" "$CACHE/templates.tpz"
  mkdir -p "$TPL" "$CACHE/tpl"
  unzip -q -o "$CACHE/templates.tpz" 'templates/android*' 'templates/version.txt' -d "$CACHE/tpl"
  cp "$CACHE"/tpl/templates/* "$TPL/"
fi

# 2. JDK 17 + Android SDK (build-tools 35.0.1, platform 35, NDK 28.1)
if [ ! -x "$JDK/bin/java" ]; then
  fetch "https://api.adoptium.net/v3/binary/latest/17/ga/linux/x64/jdk/hotspot/normal/eclipse" "$CACHE/jdk17.tar.gz"
  mkdir -p "$JDK" && tar -xzf "$CACHE/jdk17.tar.gz" -C "$JDK" --strip-components=1
fi
export JAVA_HOME="$JDK" ANDROID_HOME="$SDK" PATH="$JDK/bin:$PATH"
if [ ! -d "$SDK/ndk/28.1.13356709" ]; then
  fetch "https://dl.google.com/android/repository/commandlinetools-linux-13114758_latest.zip" "$CACHE/cmdtools.zip"
  mkdir -p "$SDK/cmdline-tools" && unzip -q -o "$CACHE/cmdtools.zip" -d "$SDK/cmdline-tools"
  [ -d "$SDK/cmdline-tools/latest" ] || mv "$SDK/cmdline-tools/cmdline-tools" "$SDK/cmdline-tools/latest"
  yes | "$SDK/cmdline-tools/latest/bin/sdkmanager" --sdk_root="$SDK" --licenses >/dev/null || true
  "$SDK/cmdline-tools/latest/bin/sdkmanager" --sdk_root="$SDK" "platform-tools" "build-tools;35.0.1" "platforms;android-35" "ndk;28.1.13356709"
fi

# 3. Signing keys (generated once, kept out of git)
mkdir -p "$ROOT/keys"
[ -f "$ROOT/keys/release.keystore" ] || keytool -genkeypair -keystore "$ROOT/keys/release.keystore" -alias policechase \
  -keyalg RSA -keysize 2048 -validity 10000 -storepass policechase -keypass policechase -dname "CN=Police Chase VR"
[ -f "$ROOT/keys/debug.keystore" ] || keytool -genkeypair -keystore "$ROOT/keys/debug.keystore" -alias androiddebugkey \
  -keyalg RSA -keysize 2048 -validity 10000 -storepass android -keypass android -dname "CN=Android Debug"

# 4. Godot editor settings pointing at the SDK and JDK
CFG="$HOME/.config/godot"; mkdir -p "$CFG"
cat > "$CFG/editor_settings-4.5.tres" <<CFGEOF
[gd_resource type="EditorSettings" format=3]

[resource]
export/android/android_sdk_path = "$SDK"
export/android/java_sdk_path = "$JDK"
export/android/debug_keystore = "$ROOT/keys/debug.keystore"
export/android/debug_keystore_user = "androiddebugkey"
export/android/debug_keystore_pass = "android"
CFGEOF

# 5. Gradle build template (android/build) for the OpenXR vendors plugin
if [ ! -f "$ROOT/android/build/build.gradle" ]; then
  mkdir -p "$ROOT/android/build"
  unzip -q -o "$TPL/android_source.zip" -d "$ROOT/android/build"
  printf '%s.stable' "$GODOT_VER" > "$ROOT/android/.build_version"
  touch "$ROOT/android/build/.gdignore"
fi

# 6. Import + export
export GODOT_ANDROID_KEYSTORE_RELEASE_PATH="$ROOT/keys/release.keystore"
export GODOT_ANDROID_KEYSTORE_RELEASE_USER=policechase
export GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD=policechase
mkdir -p "$ROOT/build"
"$GODOT" --headless --path "$ROOT" --import
"$GODOT" --headless --path "$ROOT" --export-release "Meta Quest" "$ROOT/build/PoliceChaseVR.apk"
echo "Built $ROOT/build/PoliceChaseVR.apk"
