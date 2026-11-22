#!/bin/zsh
# End-to-end install test: ./tests/e2e.sh
# Needs a logged-in macOS session. It installs Backspin for real, replacing any
# installed copy, and leaves it installed and running.
set -uo pipefail
cd "${0:A:h}/.."
DOMAIN="io.github.baseddesigner.backspin"
APP="$HOME/Applications/Backspin.app"
fail=0; typeset -a reqs
err() { print -u2 "✗ $1"; fail=1; }

# Past bug: updating while Backspin ran failed with "Bootstrap failed: 5",
# because launchd hadn't finished stopping the old copy.
for i in 1 2 3; do  # the race is intermittent, so restart more than once
  if ! log=$(./install.sh 2>&1); then
    hint=""; [[ $log == *"Bootstrap failed"* ]] && hint=" install.sh must wait for launchctl bootout to finish before bootstrap."
    err "install #$i failed: ${log##*$'\n'}.$hint"
  fi
  reqs[$i]=$(codesign -d -r- "$APP" 2>&1 | grep 'designated' | sed 's/^# //')
done

# Past bug: ad-hoc signing ties the identity to the binary's hash, so every
# rebuild lost the Accessibility permission.
[[ ${reqs[1]} == *"certificate leaf"* ]] ||
  err "Backspin is not signed with the local certificate (${reqs[1]:-no signature}). Sign with the fixed certificate, not ad hoc (--sign -)."
[[ ${reqs[1]} == "${reqs[3]}" ]] ||
  err "The designated requirement changed between installs, so macOS would drop the Accessibility permission. Reuse the same certificate."

# Past bug: settings were silently ignored. Set one, launch, read it back.
old=$(defaults read "$DOMAIN" step 2>/dev/null)
defaults write "$DOMAIN" step -float 77
out=$("$APP/Contents/MacOS/Backspin" 2>&1 & pid=$!; sleep 1; kill $pid 2>/dev/null; wait $pid 2>/dev/null)
if [[ -n $old ]]; then defaults write "$DOMAIN" step -float "$old"; else defaults delete "$DOMAIN" step; fi
launchctl kickstart -k "gui/$(id -u)/$DOMAIN" # the installed copy may have read the test value too
[[ $out == *"step: 77.0"* ]] ||
  err "Settings aren't read: wrote step 77 but Backspin started with: ${out%%$'\n'*}. Read them from UserDefaults.standard."

(( fail )) || print "✓ e2e passed"
exit $fail
