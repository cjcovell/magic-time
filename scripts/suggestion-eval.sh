#!/bin/zsh
# Asks Apple's on-device model about a set of chatty sentences and checks that every suggestion
# Magic Time would show is one its own reader understands. Needs Apple Intelligence on this Mac.
# Usage: scripts/suggestion-eval.sh [rounds per sentence, default 3]
set -euo pipefail
ROOT=${0:A:h:h}
OUT=$(mktemp -d)
swiftc -O -o "$OUT/eval" "$ROOT/Sources/TimeParser.swift" "$ROOT/Sources/NaturalTime.swift" \
  "$ROOT/Sources/Holidays.swift" "$ROOT/Sources/HinduFestivals.swift" "$ROOT/Sources/PhraseHelper.swift" \
  "$ROOT/Tests/SuggestionEval/main.swift"
"$OUT/eval" "${1:-3}"
