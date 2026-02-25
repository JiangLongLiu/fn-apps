#!/usr/bin/env bash
#
# Grafana Alloy FPK 构建脚本
# 参照 fn-terminal 的构建方式：platform=all 单包双架构、手动 tar 打包
#
# 用法:
#   ./build.sh          # 自动获取最新版本
#   ./build.sh 1.14.0   # 手动指定版本

set -e

WORKDIR="$(
  cd "$(dirname "$0")"
  pwd
)"

get_latest_version() {
  local tag
  tag=$(curl -fsSL "https://api.github.com/repos/grafana/alloy/releases/latest" \
    | grep '"tag_name"' | head -1 | sed 's/.*"v\([^"]*\)".*/\1/')
  if [ -z "$tag" ]; then
    echo "ERROR: Failed to get latest version" >&2
    exit 1
  fi
  echo "$tag"
}

ALLOY_VERSION="${1:-$(get_latest_version)}"
echo "Building Grafana Alloy v${ALLOY_VERSION} ..."

ARCHS=(x86_64 aarch64)
declare -A ALLOY_ASSET
ALLOY_ASSET[x86_64]="alloy-linux-amd64"
ALLOY_ASSET[aarch64]="alloy-linux-arm64"

for arch in "${ARCHS[@]}"; do
  asset="${ALLOY_ASSET[$arch]}"
  url="https://github.com/grafana/alloy/releases/download/v${ALLOY_VERSION}/${asset}.zip"
  zipfile="/tmp/${asset}-${ALLOY_VERSION}.zip"

  echo "Downloading Alloy for ${arch} ..."
  if [ -f "${zipfile}" ]; then
    echo "  Using cached: ${zipfile}"
  else
    curl -fsSL "${url}" -o "${zipfile}"
  fi

  rm -rf "/tmp/alloy-extract-${arch}"
  if [[ "$OSTYPE" == "darwin"* ]]; then
    command -v unzip >/dev/null 2>&1 || { brew install unzip >/dev/null 2>&1; }
  else
    command -v unzip >/dev/null 2>&1 || { apt update >/dev/null 2>&1 && apt install -y unzip >/dev/null 2>&1; }
  fi
  unzip -o "${zipfile}" -d "/tmp/alloy-extract-${arch}" >/dev/null

  mkdir -p "${WORKDIR}/app/bin/${arch}"
  mv "/tmp/alloy-extract-${arch}/${asset}" "${WORKDIR}/app/bin/${arch}/alloy"
  chmod +x "${WORKDIR}/app/bin/${arch}/alloy"
  rm -rf "/tmp/alloy-extract-${arch}"

  echo "  Done: app/bin/${arch}/alloy"
done

# Update manifest version
if [[ "$OSTYPE" == "darwin"* ]]; then
  sed -i '' "s/^version[[:space:]]*=.*/version               = ${ALLOY_VERSION}/" "${WORKDIR}/manifest"
else
  sed -i "s/^version[[:space:]]*=.*/version               = ${ALLOY_VERSION}/" "${WORKDIR}/manifest"
fi

APPNAME=$(grep '^appname' "${WORKDIR}/manifest" | awk -F= '{print $2}' | xargs)
VERSION=$(grep '^version' "${WORKDIR}/manifest" | awk -F= '{print $2}' | xargs)
PLATFORM=$(grep '^platform' "${WORKDIR}/manifest" | awk -F= '{print $2}' | xargs)

rm -f "${WORKDIR}/app.tgz" "$(dirname "${WORKDIR}")/${APPNAME}_${PLATFORM}_v${VERSION}.fpk" 2>/dev/null || true
tar -czf "${WORKDIR}/app.tgz" -C "${WORKDIR}/app" . >/dev/null 2>&1
tar -czf "$(dirname "${WORKDIR}")/${APPNAME}_${PLATFORM}_v${VERSION}.fpk" \
  -C "${WORKDIR}" cmd config wizard app.tgz ICON.PNG ICON_256.PNG manifest >/dev/null 2>&1

rm -f "${WORKDIR}/app.tgz"

# Clean up downloaded binaries
for arch in "${ARCHS[@]}"; do
  rm -rf "${WORKDIR}/app/bin/${arch}/alloy"
done

echo "Done: $(dirname "${WORKDIR}")/${APPNAME}_${PLATFORM}_v${VERSION}.fpk"

exit 0
