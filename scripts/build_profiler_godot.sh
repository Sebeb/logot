#!/usr/bin/env bash
set -euo pipefail

readonly GODOT_COMMIT="5b4e0cb0fd279832bbdd69fed5354d4e5ad26f88"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOGOT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
readonly GODOT_SOURCE_DIR="${LOGOT_GODOT_SOURCE_DIR:-${LOGOT_ROOT}/.build/godot}"
readonly GODOT_PATCH_DIR="${LOGOT_ROOT}/native/godot_patches"
readonly BUILD_PLATFORM="${1:-$(uname -s | tr '[:upper:]' '[:lower:]')}"
readonly BUILD_TARGET="${2:-editor}"
readonly BUILD_ARCH="${3:-}"
readonly BUILD_JOBS="${LOGOT_BUILD_JOBS:-4}"

case "${BUILD_PLATFORM}" in
  darwin) platform="macos" ;;
  linux) platform="linuxbsd" ;;
  mingw*|msys*|windows) platform="windows" ;;
  macos|linuxbsd) platform="${BUILD_PLATFORM}" ;;
  *) platform="${BUILD_PLATFORM}" ;;
esac

if [[ ! -d "${GODOT_SOURCE_DIR}/.git" ]]; then
  mkdir -p "$(dirname "${GODOT_SOURCE_DIR}")"
  git clone --filter=blob:none https://github.com/godotengine/godot.git "${GODOT_SOURCE_DIR}"
fi

git -C "${GODOT_SOURCE_DIR}" fetch --depth=1 origin "${GODOT_COMMIT}"
git -C "${GODOT_SOURCE_DIR}" checkout --detach "${GODOT_COMMIT}"
git -C "${GODOT_SOURCE_DIR}" reset --hard "${GODOT_COMMIT}"
# Patch-added Metal files are untracked after a hard reset. Remove only this
# generated engine subtree so patches that add files remain idempotent.
git -C "${GODOT_SOURCE_DIR}" clean -fd -- drivers/metal

for patch_file in "${GODOT_PATCH_DIR}"/*.patch; do
  [[ -e "${patch_file}" ]] || continue
  echo "Applying Godot patch: $(basename "${patch_file}")"
  git -C "${GODOT_SOURCE_DIR}" apply --check "${patch_file}"
  git -C "${GODOT_SOURCE_DIR}" apply "${patch_file}"
done

readonly MODULE_DEST="${GODOT_SOURCE_DIR}/modules/logot_profiler"
mkdir -p "${MODULE_DEST}"
rsync -a --delete "${LOGOT_ROOT}/native/logot_profiler/" "${MODULE_DEST}/"

args=(
  "platform=${platform}"
  "target=${BUILD_TARGET}"
  "module_logot_profiler_enabled=yes"
  "-j${BUILD_JOBS}"
)
if [[ "${platform}" == "macos" ]]; then
  args+=("vulkan=no" "angle=no" "accesskit=no")
fi
if [[ "${BUILD_TARGET}" == "template_debug" ]]; then
  # CI smoke tests launch the unpackaged fixture project directly.
  args+=("disable_path_overrides=no")
fi
if [[ -n "${BUILD_ARCH}" ]]; then
  args+=("arch=${BUILD_ARCH}")
fi
if [[ "${LOGOT_BUILD_TESTS:-0}" == "1" ]]; then
  args+=("tests=yes")
fi

cd "${GODOT_SOURCE_DIR}"
scons "${args[@]}"

mkdir -p "${LOGOT_ROOT}/dist/${platform}-${BUILD_ARCH:-default}-${BUILD_TARGET}"
find bin -maxdepth 1 -type f -name "*${BUILD_TARGET}*" -exec cp {} "${LOGOT_ROOT}/dist/${platform}-${BUILD_ARCH:-default}-${BUILD_TARGET}/" \;
