#!/bin/zsh
# Fast checks that need no install: ./tests/check.sh
# Each one exists because the mistake it catches really happened, or because
# the README makes a promise about it.
set -uo pipefail
cd "${0:A:h}/.."
fail=0
err() { print -u2 "✗ $1"; fail=1; }

# Swift 6 language mode turns main-actor mistakes into compile errors.
# (Past bug: a main-actor global built from a non-isolated context.)
if ! xcrun swiftc -swift-version 6 -typecheck main.swift; then
  err "main.swift must compile in Swift 6 mode. Mark UI and event-tap code @MainActor; from the C tap callback reach it through MainActor.assumeIsolated and return only Sendable values."
fi

# Past bug: a defaults suite named after the bundle ID is silently ignored, so
# no setting was ever read.
if grep -n 'UserDefaults(suiteName' main.swift; then
  err "Use UserDefaults.standard. The app's bundle ID is already its defaults domain; a suite with that name is ignored."
fi

# README, "Privacy and security": it only sees scroll events.
mask=$(grep -c 'CGEventMask(1 << CGEventType.scrollWheel.rawValue)' main.swift)
taps=$(grep -c 'CGEvent.tapCreate' main.swift)
if [[ $mask != 1 || $taps != 1 ]] || grep -nE 'CGEventType\.(key|left|right|other|mouse|flags)' main.swift; then
  err "The event tap must ask for scroll-wheel events only (one tapCreate, mask CGEventType.scrollWheel). The README promises it never sees keys, clicks or pointer movement."
fi

# README, "Privacy and security": it never goes online.
if grep -nE 'URLSession|NSURLConnection|import Network|NWConnection|CFSocket|CFStream|socket\(' main.swift; then
  err "Backspin has no network access, and the README says so. Remove the networking code."
fi

# The signing key must never be published.
if git ls-files | grep -nE 'keychain|\.p12$|\.pem$|^signing/'; then
  err "Signing material is tracked by git. Remove it with git rm --cached; the installer keeps it in ~/Library/Application Support/Backspin."
fi

(( fail )) || print "✓ checks passed"
exit $fail
