#!/usr/bin/env bash
# Build and package the Chroma Swift bindings crate using cargo-swift.
# This version lives inside the top-level `chroma/` dir, so we resolve
# the repository root as the parent directory of this script.

set -euo pipefail

# Path to repository root (one level up from script dir)
ROOT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
CRATE_DIR="$ROOT_DIR/chroma/rust/swift_bindings"

function info()  { echo -e "\033[1;34m[INFO] $*\033[0m"; }
function warn()  { echo -e "\033[1;33m[WARN] $*\033[0m"; }
function error() { echo -e "\033[1;31m[ERR ] $*\033[0m"; exit 1; }

# 1. Ensure cargo & cargo-swift available
if ! command -v cargo &>/dev/null; then error "Cargo not found."; fi
if ! cargo swift -V &>/dev/null; then
  info "Installing cargo-swift …"
  UNIFFI_VERSION=$(grep -E '^\s*uniffi\s*=' "$CRATE_DIR/Cargo.toml" | head -n1 | sed -E 's/.*"([0-9]+\.[0-9]+).*/\1/')
  case "$UNIFFI_VERSION" in
    0.25) CS_VERSION=0.5;; 0.26) CS_VERSION=0.6;; 0.27) CS_VERSION=0.7;; 0.28) CS_VERSION=0.8;; 0.29) CS_VERSION=0.9;; * ) CS_VERSION="";;
  esac
  if [[ -n "$CS_VERSION" ]]; then
    cargo install "cargo-swift@${CS_VERSION}" --locked
  else
    cargo install cargo-swift --locked
  fi
fi

# 2. Ensure Rust Apple targets
APPLE_TARGETS=("aarch64-apple-darwin" "x86_64-apple-darwin" "aarch64-apple-ios" "x86_64-apple-ios" "aarch64-apple-ios-sim")
for t in "${APPLE_TARGETS[@]}"; do
  rustup target list --installed | grep -q "^${t}$" || rustup target add "$t"
done

# 3. Optional local host build
PROFILE=${PROFILE:-release}
info "Building (profile=$PROFILE)…"
if [[ "$PROFILE" == "release" ]]; then
  cargo build --manifest-path "$CRATE_DIR/Cargo.toml" --release
else
  cargo build --manifest-path "$CRATE_DIR/Cargo.toml"
fi

# 4. Package via cargo-swift
info "Packaging Swift module → Chroma …"
(
  cd "$CRATE_DIR"
  cargo swift package -y -n Chroma --xcframework-name ChromaFFI
)

info "✅ Swift Package ready at $CRATE_DIR/Chroma"
