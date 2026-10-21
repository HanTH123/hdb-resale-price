#!/usr/bin/env bash
# Runs one HDB_BDDFramework test suite through the BDDFramework REST runner
# and fails (exit 1) unless the suite reports IsSuccess = true.
#
# Usage:   scripts/run-bdd-suite.sh <ScreenName>
# Needs:   OUTSYSTEMS_BASE_URL, e.g. https://myenv.outsystemscloud.com
#          curl and jq
# Output:  the raw JSON response is saved to results/<ScreenName>.json

set -euo pipefail

suite="${1:?Usage: $0 <ScreenName>}"
base_url="${OUTSYSTEMS_BASE_URL:?Set OUTSYSTEMS_BASE_URL, e.g. https://myenv.outsystemscloud.com}"
url="${base_url%/}/BDDFramework/rest/v2/BDDTestRunner/HDB_BDDFramework/${suite}"
out_dir="results"
out_file="${out_dir}/${suite}.json"

mkdir -p "$out_dir"
echo "Running ${suite}: ${url}"

http_code=$(curl --silent --show-error \
  --max-time "${BDD_TIMEOUT_SECONDS:-300}" \
  --retry 2 --retry-delay 10 --retry-all-errors \
  --output "$out_file" --write-out '%{http_code}' \
  "$url") || { echo "::error title=${suite}::Request failed (network error or timeout)"; exit 1; }

if [[ "$http_code" != "200" ]]; then
  echo "::error title=${suite}::Runner returned HTTP ${http_code}"
  cat "$out_file" || true
  exit 1
fi

if ! jq empty "$out_file" 2>/dev/null; then
  echo "::error title=${suite}::Runner response is not JSON"
  cat "$out_file"
  exit 1
fi

echo "Response:"
jq . "$out_file"

# Scenario-level detail, if the runner includes it.
failed=$(jq -c '[.TestScenarioResults[]? | select((.IsSuccess // true) == false)]' "$out_file")
total=$(jq '[.TestScenarioResults[]?] | length' "$out_file")

if jq -e '.IsSuccess == true' "$out_file" >/dev/null; then
  echo "PASS ${suite} (${total} scenario result(s))"
  [[ -n "${GITHUB_STEP_SUMMARY:-}" ]] && echo "| ${suite} | ✅ Passed | ${total} |" >> "$GITHUB_STEP_SUMMARY"
  exit 0
fi

echo "::error title=${suite}::Suite failed (IsSuccess is not true)"
if [[ "$failed" != "[]" ]]; then
  echo "Failed scenarios:"
  echo "$failed" | jq .
fi
[[ -n "${GITHUB_STEP_SUMMARY:-}" ]] && echo "| ${suite} | ❌ Failed | ${total} |" >> "$GITHUB_STEP_SUMMARY"
exit 1
