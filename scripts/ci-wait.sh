#!/bin/bash
# Script to wait for CI to complete on a PR
# Usage: ./ci-wait.sh <pr_number> [poll_interval_seconds]

set -e

REPO="${REPO:-konstin/maturin}"
POLL_INTERVAL="${2:-30}"

if [ -z "$1" ]; then
    echo "Usage: $0 <pr_number> [poll_interval_seconds]"
    echo ""
    echo "Waits for all CI checks to complete on a PR."
    echo ""
    echo "Arguments:"
    echo "  pr_number: The PR number to monitor"
    echo "  poll_interval: Seconds between checks (default: 30)"
    echo ""
    echo "Environment variables:"
    echo "  REPO: Repository (default: konstin/maturin)"
    echo "  GITHUB_TOKEN: GitHub token for API access"
    exit 1
fi

# Check if we have a token
if [ -z "$GITHUB_TOKEN" ]; then
    AUTH_HEADER=""
else
    AUTH_HEADER="Authorization: token $GITHUB_TOKEN"
fi

fetch_api() {
    local url=$1
    if [ -n "$AUTH_HEADER" ]; then
        curl -s -H "$AUTH_HEADER" -H "Accept: application/vnd.github.v3+json" "$url"
    else
        curl -s -H "Accept: application/vnd.github.v3+json" "$url"
    fi
}

PR_NUMBER=$1

echo "Watching CI for PR #$PR_NUMBER in $REPO..."
echo "Polling every $POLL_INTERVAL seconds"
echo ""

# Get the PR to find the head SHA
PR_DATA=$(fetch_api "https://api.github.com/repos/$REPO/pulls/$PR_NUMBER")
HEAD_SHA=$(echo "$PR_DATA" | python3 -c "import json,sys; print(json.load(sys.stdin).get('head', {}).get('sha', ''))")

if [ -z "$HEAD_SHA" ]; then
    echo "Error: Could not find PR #$PR_NUMBER"
    exit 1
fi

echo "Head SHA: $HEAD_SHA"
echo ""

while true; do
    # Get check runs for this commit
    CHECK_RUNS=$(fetch_api "https://api.github.com/repos/$REPO/commits/$HEAD_SHA/check-runs?per_page=100")

    # Parse status
    STATUS=$(echo "$CHECK_RUNS" | python3 -c "
import json
import sys
from datetime import datetime

data = json.load(sys.stdin)
if 'check_runs' not in data:
    print('error')
    sys.exit(1)

runs = data['check_runs']
total = len(runs)
completed = 0
in_progress = 0
queued = 0
failed = 0
success = 0

for run in runs:
    status = run['status']
    conclusion = run.get('conclusion', '')

    if status == 'completed':
        completed += 1
        if conclusion == 'success':
            success += 1
        elif conclusion == 'failure':
            failed += 1
    elif status == 'in_progress':
        in_progress += 1
    else:
        queued += 1

now = datetime.now().strftime('%H:%M:%S')

if total == 0:
    print(f'{now} | No checks found yet...')
elif failed > 0:
    print(f'{now} | FAILED | {success} passed, {failed} failed, {in_progress} running, {queued} queued')
    print('status:failed')
elif completed == total:
    print(f'{now} | DONE | All {total} checks passed!')
    print('status:done')
else:
    print(f'{now} | RUNNING | {completed}/{total} complete ({in_progress} running, {queued} queued)')
    print('status:running')
")

    echo "$STATUS" | head -1

    # Check if we're done
    if echo "$STATUS" | grep -q "status:done"; then
        echo ""
        echo "✅ All CI checks have passed!"
        exit 0
    elif echo "$STATUS" | grep -q "status:failed"; then
        echo ""
        echo "❌ Some CI checks have failed!"
        exit 1
    fi

    sleep "$POLL_INTERVAL"
done
