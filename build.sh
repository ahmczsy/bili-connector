#!/bin/sh
# Build zju-connect executables for Linux and macOS.
#
# Usage:
#   ./build.sh              # common targets: darwin/amd64 darwin/arm64 linux/amd64 linux/arm64
#   ./build.sh --all        # full CI matrix for linux/darwin (incl. 386, arm v5-v7, riscv64, mips)
#   ./build.sh darwin/arm64 linux/amd64   # custom target list
#
# Output: build_assets/zju-connect-<goos>-<goarch>[v<arm>]
set -eu

REPO_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
cd "$REPO_ROOT"

ASSET_DIR=build_assets
DEFAULT_TARGETS="darwin/amd64 darwin/arm64 linux/amd64 linux/arm64"
ALL_TARGETS="
  darwin/amd64 darwin/arm64
  linux/amd64 linux/386 linux/arm64
  linux/armv5 linux/armv6 linux/armv7
  linux/riscv64 linux/mips linux/mipsle linux/mips64 linux/mips64le
"

TARGETS=$DEFAULT_TARGETS
if [ "${1:-}" = "--all" ]; then
  TARGETS=$ALL_TARGETS
  shift
fi
if [ "$#" -gt 0 ]; then
  TARGETS=$*
fi

# go.mod requires a newer Go than many systems have installed; allow the
# automatic toolchain switch. GOSUMDB=off disables toolchain downloads, so
# re-enable the checksum database for this script when it is turned off.
export GOTOOLCHAIN=auto
if [ "$(GOTOOLCHAIN=local go env GOSUMDB 2>/dev/null)" = "off" ]; then
  export GOSUMDB=sum.golang.org
fi

if git describe --exact-match --tags >/dev/null 2>&1; then
  VERSION=$(git describe --exact-match --tags)
  VERSION_FLAGS="-X main.zjuConnectVersion=${VERSION}"
else
  VERSION="dev-$(git rev-parse --short HEAD)"
  VERSION_FLAGS="-X main.zjuConnectVersion=dev -X main.CommitID=$(git rev-parse --short HEAD)"
fi

mkdir -p "$ASSET_DIR"
echo "Building zju-connect ${VERSION} -> ${ASSET_DIR}/"

FAILED=""
for target in $TARGETS; do
  case "$target" in
    darwin/*|linux/*) ;;
    *) echo "Skipping unsupported target: $target" >&2; continue ;;
  esac

  GOOS=${target%%/*}
  GOARCH=${target#*/}
  GOARM=""
  SUFFIX="-${GOOS}-${GOARCH}"
  case "$GOARCH" in
    armv[0-9])
      GOARM=${GOARCH#armv}
      GOARCH=arm
      SUFFIX="-${GOOS}-armv${GOARM}"
      ;;
  esac

  echo "==> ${SUFFIX#-}"
  if ! CGO_ENABLED=0 GOOS=$GOOS GOARCH=$GOARCH GOARM=$GOARM \
      go build -trimpath \
      -ldflags "-s -w -buildid= ${VERSION_FLAGS}" \
      -o "${ASSET_DIR}/zju-connect${SUFFIX}" .; then
    echo "FAILED: ${SUFFIX#-}" >&2
    FAILED="$FAILED ${SUFFIX#-}"
  fi
done

echo "Done:"
ls -l "$ASSET_DIR"/zju-connect-* 2>/dev/null || true
if [ -n "$FAILED" ]; then
  echo "Failed targets:${FAILED}" >&2
  exit 1
fi
