#!/usr/bin/env bash
#
# Builds build/Tripad.app from the SwiftPM executable. No Xcode required.
#
# The signing identity matters more than it looks: macOS keys the Accessibility
# grant to the code signature, so a plain ad-hoc signature (whose designated
# requirement is the cdhash) invalidates the permission on every rebuild. We
# therefore sign with a stable self-signed certificate, created once.

set -euo pipefail

APP_NAME="Tripad"
BUNDLE_ID="com.aobasar.Tripad"
VERSION="0.1.0"
IDENTITY_NAME="Tripad Local"
MIN_MACOS="14.0"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="$ROOT/build"
APP="$BUILD_DIR/$APP_NAME.app"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"
ICON_PNG="$ROOT/Assets/AppIcon.png"

# Builds AppIcon.icns from the 1024 master. Regenerate that master with
# scripts/make-appicon.swift when the artwork changes.
make_icns() {
  local out="$1"
  local iconset
  iconset="$(mktemp -d)/AppIcon.iconset"
  mkdir -p "$iconset"

  local size
  for size in 16 32 128 256 512; do
    sips -z "$size" "$size" "$ICON_PNG" \
      --out "$iconset/icon_${size}x${size}.png" > /dev/null
    sips -z "$((size * 2))" "$((size * 2))" "$ICON_PNG" \
      --out "$iconset/icon_${size}x${size}@2x.png" > /dev/null
  done

  iconutil --convert icns "$iconset" --output "$out"
  rm -rf "$(dirname "$iconset")"
}

has_identity() {
  security find-identity -v -p codesigning 2>/dev/null | grep -q "$IDENTITY_NAME"
}

ensure_identity() {
  if has_identity; then
    return 0
  fi

  echo "==> Creating self-signed code signing identity '$IDENTITY_NAME'"
  local tmp
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN

  cat > "$tmp/openssl.cnf" <<EOF
[ req ]
distinguished_name = dn
x509_extensions    = v3
prompt             = no

[ dn ]
CN = $IDENTITY_NAME

[ v3 ]
basicConstraints    = critical,CA:false
keyUsage            = critical,digitalSignature
extendedKeyUsage    = critical,codeSigning
subjectKeyIdentifier = hash
EOF

  # System LibreSSL on purpose: OpenSSL 3 writes a PKCS#12 MAC that
  # /usr/bin/security cannot verify, and Homebrew's openssl may be first on PATH.
  local openssl="/usr/bin/openssl"
  local p12_pass="tripad-import"

  "$openssl" req -x509 -newkey rsa:2048 -nodes -days 3650 \
    -keyout "$tmp/key.pem" -out "$tmp/cert.pem" -config "$tmp/openssl.cnf" 2>/dev/null

  "$openssl" pkcs12 -export -inkey "$tmp/key.pem" -in "$tmp/cert.pem" \
    -name "$IDENTITY_NAME" -out "$tmp/identity.p12" -passout "pass:$p12_pass" 2>/dev/null

  # -T lets codesign use the private key without a confirmation dialog per build.
  security import "$tmp/identity.p12" -k "$KEYCHAIN" -P "$p12_pass" \
    -T /usr/bin/codesign -T /usr/bin/security > /dev/null

  # codesign refuses a signer whose chain does not end in a trusted root.
  # This one prompts for the login password once; it is a user-domain setting.
  security add-trusted-cert -r trustRoot -p codeSign -k "$KEYCHAIN" "$tmp/cert.pem" \
    || echo "!!  Could not set trust automatically — see README, 'Signing'."
}

echo "==> Building (release, arm64)"
swift build -c release --arch arm64
BIN="$(swift build -c release --arch arm64 --show-bin-path)/$APP_NAME"

echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/$APP_NAME"

if [[ -f "$ICON_PNG" ]]; then
  echo "==> Building icon"
  make_icns "$APP/Contents/Resources/AppIcon.icns"
else
  echo "!!  $ICON_PNG missing — building without an icon."
fi

cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key>
	<string>en</string>
	<key>CFBundleExecutable</key>
	<string>$APP_NAME</string>
	<key>CFBundleIconFile</key>
	<string>AppIcon</string>
	<key>CFBundleIconName</key>
	<string>AppIcon</string>
	<key>CFBundleIdentifier</key>
	<string>$BUNDLE_ID</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleName</key>
	<string>$APP_NAME</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>$VERSION</string>
	<key>CFBundleVersion</key>
	<string>$VERSION</string>
	<key>LSMinimumSystemVersion</key>
	<string>$MIN_MACOS</string>
	<key>LSUIElement</key>
	<true/>
	<key>NSHighResolutionCapable</key>
	<true/>
</dict>
</plist>
EOF

printf 'APPL????' > "$APP/Contents/PkgInfo"

ensure_identity

if has_identity; then
  echo "==> Signing with '$IDENTITY_NAME'"
  codesign --force --sign "$IDENTITY_NAME" "$APP"
else
  echo "!!  No stable identity available — falling back to ad-hoc."
  echo "!!  Accessibility permission will have to be re-granted after every build."
  codesign --force --sign - "$APP"
fi

codesign --verify --verbose=2 "$APP"

echo "==> Done: $APP"
