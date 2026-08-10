#!/bin/zsh
set -euo pipefail

script_dir="${0:A:h}"
project_dir="${script_dir:h}"
stress_events="${GAMELOG_STRESS_EVENTS:-3600000}"

cd "$project_dir"
GAMELOG_STRESS_EVENTS="$stress_events" /usr/bin/xcodebuild \
  -project GameLog.xcodeproj \
  -scheme GameLog \
  -configuration Debug \
  -derivedDataPath .build/xcode \
  -destination "platform=macOS" \
  CODE_SIGNING_ALLOWED=NO \
  test \
  -only-testing:GameLogTests/PerformanceBaselineTests/testBoundedPipelineProcessesSyntheticSustainedInput
