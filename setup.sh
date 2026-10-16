#!/bin/sh

set -e

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT_DIR"

echo "==== Checking Homebrew installation ===="
if ! command -v brew >/dev/null 2>&1; then
  echo "Homebrew not found. Installing..."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
else
  echo "Homebrew is installed."
fi

echo "==== Installing or upgrading SwiftLint ===="
brew install swiftlint || brew upgrade swiftlint

echo "==== Installing or upgrading SwiftFormat ===="
brew install swiftformat || brew upgrade swiftformat

# Non-fatal preflight: the walk runner orchestrates these at run time, not build time.
echo "==== Preflight: simulator toolchain ===="
xcrun simctl help >/dev/null 2>&1 || echo "WARNING: 'xcrun simctl' unavailable — install Xcode before running walks."

echo "==== Activating git hooks ===="
git config core.hooksPath githooks
chmod +x "$ROOT_DIR/githooks/"*

# A checkout's own extra setup, if it has any.
if [ -f "$ROOT_DIR/setup.local.sh" ]; then
  sh "$ROOT_DIR/setup.local.sh"
fi

echo "==== Setup complete! ===="
