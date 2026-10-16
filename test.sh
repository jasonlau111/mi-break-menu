#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
swift test
cargo test --locked --manifest-path core/Cargo.toml
cargo clippy --locked --manifest-path core/Cargo.toml -- -D warnings
swift build --product MiBreak
