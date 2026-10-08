#!/usr/bin/env bash
# Install the dif CLI on a GitHub Actions runner.
#
# Downloads the prebuilt binary for the runner's OS and architecture from the
# dif-sh/dif GitHub release, checks it against the published .sha256 file,
# and adds it to PATH for the rest of the job. Needs bash, curl and tar
# (plus unzip or PowerShell on Windows). Does not need Node.
#
# Inputs (environment):
#   DIF_VERSION            "latest" (default), "0.6.3" or "v0.6.3"
#   DIF_RELEASE_BASE_URL   override for mirrors; default
#                          https://github.com/dif-sh/dif/releases

set -euo pipefail

REPO="dif-sh/dif"
BASE_URL="${DIF_RELEASE_BASE_URL:-https://github.com/${REPO}/releases}"
BASE_URL="${BASE_URL%/}"
VERSION="${DIF_VERSION:-latest}"

fail() {
  echo "::error title=dif install::$*"
  exit 1
}

# --- target -----------------------------------------------------------------

os="${RUNNER_OS:-$(uname -s)}"
arch="${RUNNER_ARCH:-$(uname -m)}"
case "$arch" in
  X64 | x86_64 | amd64) arch="x86_64" ;;
  ARM64 | arm64 | aarch64) arch="aarch64" ;;
  *) fail "unsupported architecture: $arch" ;;
esac

ext="tar.gz"
bin="dif"
case "$os" in
  Linux) target="${arch}-unknown-linux-musl" ;;
  macOS | Darwin) target="${arch}-apple-darwin" ;;
  Windows | MINGW* | MSYS* | CYGWIN*)
    [ "$arch" = "x86_64" ] || fail "dif has no Windows arm64 binary. Use an x64 Windows runner."
    target="x86_64-pc-windows-msvc"
    ext="zip"
    bin="dif.exe"
    ;;
  *) fail "unsupported runner OS: $os" ;;
esac

# --- version ----------------------------------------------------------------

if [ -z "$VERSION" ] || [ "$VERSION" = "latest" ]; then
  # /releases/latest redirects to /releases/tag/<tag>. Reading the redirect
  # needs no API token and does not count against the API rate limit.
  latest_url="$(curl -fsSLI --retry 3 -o /dev/null -w '%{url_effective}' "${BASE_URL}/latest")" ||
    fail "could not resolve the latest dif release from ${BASE_URL}/latest"
  tag="${latest_url##*/}"
  case "$tag" in
    v[0-9]*) ;;
    *) fail "could not resolve the latest dif release (got '${latest_url}'). Set the version input, for example 0.6.3." ;;
  esac
else
  tag="v${VERSION#v}"
fi

# --- download and verify ----------------------------------------------------

archive="dif-${target}.${ext}"
url="${BASE_URL}/download/${tag}/${archive}"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

echo "Downloading dif ${tag} for ${target}"
echo "  ${url}"
curl -fsSL --retry 3 --retry-delay 2 -o "${tmp}/${archive}" "$url" ||
  fail "download failed: ${url}. Check that release ${tag} exists at https://github.com/${REPO}/releases."
curl -fsSL --retry 3 --retry-delay 2 -o "${tmp}/${archive}.sha256" "${url}.sha256" ||
  fail "could not download the checksum ${url}.sha256. Refusing to install an unverified binary."

# The .sha256 file is "<hex>  <name>" on macOS and Linux and a bare uppercase
# hex line on Windows, so take the first 64 hex characters and lowercase them.
expected="$(tr -d '\000\r' <"${tmp}/${archive}.sha256" | grep -Eo '[0-9A-Fa-f]{64}' | head -n 1 | tr 'A-F' 'a-f' || true)"
[ -n "$expected" ] || fail "malformed checksum file for ${archive}"

if command -v sha256sum >/dev/null 2>&1; then
  actual="$(sha256sum "${tmp}/${archive}" | cut -c1-64)"
elif command -v shasum >/dev/null 2>&1; then
  actual="$(shasum -a 256 "${tmp}/${archive}" | cut -c1-64)"
else
  fail "no sha256sum or shasum on this runner; cannot verify the download"
fi
actual="$(printf '%s' "$actual" | tr 'A-F' 'a-f')"

[ "$expected" = "$actual" ] ||
  fail "checksum mismatch for ${archive}: expected ${expected}, got ${actual}"
echo "Checksum verified (sha256 ${actual})"

# --- extract and install ----------------------------------------------------

mkdir -p "${tmp}/out"
if [ "$ext" = "zip" ]; then
  if command -v unzip >/dev/null 2>&1; then
    unzip -q "${tmp}/${archive}" -d "${tmp}/out"
  else
    powershell -NoProfile -Command \
      "Expand-Archive -Path '${tmp}/${archive}' -DestinationPath '${tmp}/out' -Force"
  fi
else
  tar -xzf "${tmp}/${archive}" -C "${tmp}/out"
fi

# Release archives wrap the binary in a top-level dif-<target>/ directory.
found="$(find "${tmp}/out" -type f -name "$bin" | head -n 1)"
[ -n "$found" ] || fail "binary ${bin} not found in ${archive}"

install_dir="${RUNNER_TEMP:-${TMPDIR:-/tmp}}/dif-action/${tag}/${target}"
mkdir -p "$install_dir"
cp "$found" "${install_dir}/${bin}"
chmod +x "${install_dir}/${bin}"

installed="$("${install_dir}/${bin}" --version)"
echo "Installed ${installed} at ${install_dir}/${bin}"

# GITHUB_PATH wants a native path on Windows.
path_entry="$install_dir"
if command -v cygpath >/dev/null 2>&1; then
  path_entry="$(cygpath -w "$install_dir")"
fi

if [ -n "${GITHUB_PATH:-}" ]; then
  echo "$path_entry" >>"$GITHUB_PATH"
fi
if [ -n "${GITHUB_OUTPUT:-}" ]; then
  {
    echo "version=${installed#dif }"
    echo "path=${path_entry}"
  } >>"$GITHUB_OUTPUT"
fi
