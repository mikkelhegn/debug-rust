#!/usr/bin/env bash
set -euo pipefail

# Debugging prerequisites:
# - gdb: used by the "Attach to Spin trigger (gdb)" launch config
# - procps (pgrep): used by the "Debug Spin App" launch config to find the trigger process
sudo apt-get update
sudo apt-get install -y --no-install-recommends gdb procps
sudo rm -rf /var/lib/apt/lists/*

# Rust Wasm targets (wasm32-wasi was removed from Rust; wasip1/wasip2 replace it)
rustup target add wasm32-wasip1 wasm32-wasip2

# wasmtime - official installer, supports x86_64 and arm64
curl -fsSL https://wasmtime.dev/install.sh | bash
sudo ln -sf "$HOME/.wasmtime/bin/wasmtime" /usr/local/bin/wasmtime

# Spin CLI - official installer from the CNCF Spin project
curl -fsSL https://spinframework.dev/downloads/install.sh | bash
sudo mv spin /usr/local/bin/

wasmtime --version
spin --version
