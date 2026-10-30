#!/usr/bin/env bash
# 로컬(맥)에서 미서명 IPA 빌드. CI(.github/workflows/release.yml)와 동일 절차.
# 사용: scripts/make-ipa.sh   ->  dist/korail4iOS.ipa (+ .tipa)
set -euo pipefail
cd "$(dirname "$0")/.."

command -v xcodegen >/dev/null || { echo "xcodegen 필요: brew install xcodegen"; exit 1; }

xcodegen generate
xcodebuild \
  -project korail4iOS.xcodeproj \
  -scheme korail4iOS \
  -configuration Release \
  -sdk iphoneos \
  -derivedDataPath build \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" \
  build

APP="build/Build/Products/Release-iphoneos/korail4iOS.app"
rm -rf Payload dist && mkdir -p Payload dist
cp -R "$APP" Payload/
zip -qr dist/korail4iOS.ipa Payload
cp dist/korail4iOS.ipa dist/korail4iOS.tipa
echo "완료: dist/korail4iOS.ipa  (TrollStore로 설치)"
