#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
# Archive only. Never uploads, accepts account agreements, or creates App Store records.
xcodebuild -project Lingua.xcodeproj -scheme Lingua -configuration Release \
  -destination 'generic/platform=macOS' -derivedDataPath build/StoreDerivedData \
  -clonedSourcePackagesDirPath build/SourcePackages -skipMacroValidation \
  -archivePath "$PWD/build/Lingua.xcarchive" archive "$@"
