#!/bin/sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
TEST_DIR="$(mktemp -d)"
trap 'rm -rf "$TEST_DIR"' EXIT

cd "$ROOT"
swiftc \
  -module-cache-path "$TEST_DIR/ModuleCache" \
  Hetkia/Features/Onboarding/OnboardingFlowModel.swift \
  Tests/OnboardingFlowSmokeTests.swift \
  -o "$TEST_DIR/OnboardingFlowSmokeTests"
"$TEST_DIR/OnboardingFlowSmokeTests"
