#!/bin/bash
# Script to check CI status for a PR or workflow run
# Usage: ./ci-status.sh [pr_number|run_id]

set -e

REPO="${REPO:-konstin/maturin}"

if [ -z "$1" ]; then
    echo "Usage: $0 <pr_number|run_id>"
    echo "  pr_number: Check status of all checks for a PR"
    echo "  run_id: Check status of a specific workflow run"
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

# Determine if input is a PR number or run ID
INPUT=$1

if [ ${#INPUT} -lt 8 ]; then
    # Likely a PR number
    echo "Fetching check runs for PR #$INPUT in $REPO..."

    # Get the PR to find the head SHA
    PR_DATA=$(fetch_api "https://api.github.com/repos/$REPO/pulls/$INPUT")
    HEAD_SHA=$(echo "$PR_DATA" | grep -o '"sha": "[^"]*"' | head -1 | cut -d'"' -f4)

    if [ -z "$HEAD_SHA" ]; then
        echo "Error: Could not find PR #$INPUT"
        exit 1
    fi

    echo "Head SHA: $HEAD_SHA"
    echo ""

    # Get check runs for this commit
    CHECK_RUNS=$(fetch_api "https://api.github.com/repos/$REPO/commits/$HEAD_SHA/check-runs?per_page=100")

    # Parse and display check runs
    echo "Check Runs Status:"
    echo "=================="
    echo "$CHECK_RUNS" | python3 -c "
import json
import sys

data = json.load(sys.stdin)
if 'check_runs' not in data:
    print('No check runs found or API error')
    sys.exit(1)

runs = data['check_runs']
completed = 0
in_progress = 0
failed = 0
success = 0

for run in runs:
    name = run['name']
    status = run['status']
    conclusion = run.get('conclusion', 'N/A')

    if status == 'completed':
        completed += 1
        if conclusion == 'success':
            success += 1
            icon = '✅'
        elif conclusion == 'failure':
            failed += 1
            icon = '❌'
        elif conclusion == 'skipped':
            icon = '⏭️'
        else:
            icon = '⚠️'
    else:
        in_progress += 1
        icon = '🔄'

    print(f'{icon} {name}: {status} ({conclusion})')

print('')
print(f'Summary: {success} passed, {failed} failed, {in_progress} in progress')
if failed > 0:
    print('⚠️  Some checks have failed!')
elif in_progress > 0:
    print('⏳ Checks still running...')
else:
    print('✅ All checks passed!')
"
else
    # Likely a run ID
    echo "Fetching workflow run $INPUT from $REPO..."

    RUN_DATA=$(fetch_api "https://api.github.com/repos/$REPO/actions/runs/$INPUT")

    echo "$RUN_DATA" | python3 -c "
import json
import sys

data = json.load(sys.stdin)
if 'id' not in data:
    print('Error: Could not find run')
    sys.exit(1)

print(f'Workflow: {data.get(\"name\", \"N/A\")}')
print(f'Status: {data.get(\"status\", \"N/A\")}')
print(f'Conclusion: {data.get(\"conclusion\", \"N/A\")}')
print(f'Started: {data.get(\"run_started_at\", \"N/A\")}')
print(f'URL: {data.get(\"html_url\", \"N/A\")}')
"
fi
