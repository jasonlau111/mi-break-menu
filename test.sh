#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
swift test
cargo test --locked --manifest-path core/Cargo.toml
cargo clippy --locked --manifest-path core/Cargo.toml -- -D warnings
xcrun swiftc -swift-version 6 -parse-as-library -default-isolation MainActor -enable-upcoming-feature NonisolatedNonsendingByDefault -typecheck Timing/*.swift Sources/*.swift
