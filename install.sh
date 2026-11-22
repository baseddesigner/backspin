#!/bin/zsh
# Builds Backspin.app into ~/Applications and starts it at login via a LaunchAgent.
#   ./install.sh            build + install + (re)start
#   ./install.sh uninstall  stop + remove
set -euo pipefail
cd "${0:A:h}"

NAME="Backspin"
LABEL="io.github.baseddesigner.backspin"
APP="$HOME/Applications/$NAME.app"
AGENT="$HOME/Library/LaunchAgents/$LABEL.plist"
LOG="/tmp/backspin.log"
UID_=$(id -u)

if [[ "${1:-}" == "uninstall" ]]; then
  launchctl bootout "gui/$UID_/$LABEL" 2>/dev/null || true
  rm -f "$AGENT"
  rm -rf "$APP"   # signing/ is kept so a reinstall reuses the same certificate
  echo "$NAME removed. You can also remove it from System Settings → Privacy & Security → Accessibility."
  exit 0
fi

if (( ${$(sw_vers -productVersion)%%.*} < 14 )); then
  echo "$NAME needs macOS 14 (Sonoma) or later." >&2
  exit 1
fi

mkdir -p "$APP/Contents/MacOS" "$HOME/Library/LaunchAgents"
xcrun swiftc -O main.swift -o "$APP/Contents/MacOS/$NAME"

cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>$LABEL</string>
  <key>CFBundleName</key><string>$NAME</string>
  <key>CFBundleExecutable</key><string>$NAME</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
</dict></plist>
EOF

# Sign with a fixed, self-signed certificate (created once, kept in ./signing/)
# so macOS recognises rebuilds as the same app and keeps the Accessibility permission.
# The certificate is personal to your Mac; never commit signing/.
KC="$PWD/signing/backspin.keychain-db"
CERT_NAME="$NAME Local Signing"
if [[ ! -f "$KC" ]]; then
  echo "Creating signing certificate (one time)…"
  mkdir -p signing
  tmp=$(mktemp -d)
  cat > "$tmp/cert.cnf" <<EOF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $CERT_NAME
[ext]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
EOF
  /usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 7300 -config "$tmp/cert.cnf" \
    -keyout "$tmp/key.pem" -out "$tmp/cert.pem" 2>/dev/null
  /usr/bin/openssl pkcs12 -export -inkey "$tmp/key.pem" -in "$tmp/cert.pem" \
    -name "$CERT_NAME" -out "$tmp/id.p12" -passout pass:backspin
  # A separate keychain with an empty password: holds only this signing key,
  # so the login keychain and its password are never involved.
  search_list=("${(@f)$(security list-keychains -d user | sed -e 's/^ *"//' -e 's/"$//')}")
  security create-keychain -p "" "$KC"
  security list-keychains -d user -s "${search_list[@]}" # keep it out of Keychain Access
  security set-keychain-settings "$KC"                    # never auto-lock
  security unlock-keychain -p "" "$KC"
  security import "$tmp/id.p12" -k "$KC" -P backspin -T /usr/bin/codesign >/dev/null
  security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "" "$KC" >/dev/null
  rm -rf "$tmp"
fi
security unlock-keychain -p "" "$KC"
codesign --force --sign "$CERT_NAME" --keychain "$KC" --identifier "$LABEL" "$APP"

cat > "$AGENT" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key><array><string>$APP/Contents/MacOS/$NAME</string></array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>ProcessType</key><string>Interactive</string>
  <key>StandardErrorPath</key><string>$LOG</string>
</dict></plist>
EOF

launchctl bootout "gui/$UID_/$LABEL" 2>/dev/null || true
launchctl bootstrap "gui/$UID_" "$AGENT"
echo "$NAME installed at $APP and running. Log: $LOG"
echo "First install? Turn it on in System Settings → Privacy & Security → Accessibility."
