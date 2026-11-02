#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
# A separate package verifies core logic/UI without compiling Metal or downloading weights.
mkdir -p .build/check
cat > .build/check/Package.swift <<'MANIFEST'
// swift-tools-version: 6.2
import PackageDescription
let package = Package(name: "LinguaCheck", platforms: [.macOS(.v14)], targets: [
 .target(name: "TranslationCore", resources: [.copy("Resources/InterfaceStrings.json")]),
 .executableTarget(name: "LinguaMac", dependencies: ["TranslationCore"], resources: [.copy("Resources/AppIcon.png"), .copy("Resources/Legal")]),
 .testTarget(name: "TranslationCoreTests", dependencies: ["TranslationCore", "LinguaMac"])
])
MANIFEST
[ -e .build/check/Sources ] || ln -s ../../Sources .build/check/Sources
[ -e .build/check/Tests ] || ln -s ../../Tests .build/check/Tests
swift test --package-path .build/check
