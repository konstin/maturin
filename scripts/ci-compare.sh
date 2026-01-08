#!/bin/bash
# Script to compare CI job times between two workflow runs
# Usage: ./ci-compare.sh <run_id_baseline> <run_id_optimized>

set -e

REPO="${REPO:-konstin/maturin}"

if [ -z "$2" ]; then
    echo "Usage: $0 <run_id_baseline> <run_id_optimized>"
    echo ""
    echo "Compares job timing between two workflow runs to measure optimization impact."
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

RUN_BASELINE=$1
RUN_OPTIMIZED=$2

echo "Comparing CI runs:"
echo "  Baseline:  $RUN_BASELINE"
echo "  Optimized: $RUN_OPTIMIZED"
echo ""

# Fetch jobs for both runs and save to temp files
BASELINE_FILE=$(mktemp)
OPTIMIZED_FILE=$(mktemp)

fetch_api "https://api.github.com/repos/$REPO/actions/runs/$RUN_BASELINE/jobs?per_page=100" > "$BASELINE_FILE"
fetch_api "https://api.github.com/repos/$REPO/actions/runs/$RUN_OPTIMIZED/jobs?per_page=100" > "$OPTIMIZED_FILE"

# Compare with Python
python3 - "$BASELINE_FILE" "$OPTIMIZED_FILE" << 'EOF'
import json
import sys
from datetime import datetime

def parse_duration(started, completed):
    if not started or not completed:
        return None
    start = datetime.fromisoformat(started.replace('Z', '+00:00'))
    end = datetime.fromisoformat(completed.replace('Z', '+00:00'))
    return (end - start).total_seconds()

def format_duration(seconds):
    if seconds is None:
        return "N/A"
    minutes = int(seconds // 60)
    secs = int(seconds % 60)
    return f"{minutes}m {secs}s"

def format_diff(baseline, optimized):
    if baseline is None or optimized is None:
        return "N/A"
    diff = optimized - baseline
    pct = (diff / baseline) * 100 if baseline > 0 else 0
    if diff < 0:
        return f"-{format_duration(abs(diff))} ({pct:.1f}%)"
    else:
        return f"+{format_duration(diff)} (+{pct:.1f}%)"

baseline_file = sys.argv[1]
optimized_file = sys.argv[2]

with open(baseline_file) as f:
    baseline_data = json.load(f)
with open(optimized_file) as f:
    optimized_data = json.load(f)

baseline_jobs = {j['name']: j for j in baseline_data.get('jobs', [])}
optimized_jobs = {j['name']: j for j in optimized_data.get('jobs', [])}

all_jobs = set(baseline_jobs.keys()) | set(optimized_jobs.keys())

print(f"{'Job Name':<50} {'Baseline':<12} {'Optimized':<12} {'Difference':<20}")
print("=" * 94)

total_baseline = 0
total_optimized = 0

for job_name in sorted(all_jobs):
    baseline = baseline_jobs.get(job_name)
    optimized = optimized_jobs.get(job_name)

    baseline_dur = None
    optimized_dur = None

    if baseline and baseline.get('conclusion') == 'success':
        baseline_dur = parse_duration(baseline.get('started_at'), baseline.get('completed_at'))
        if baseline_dur:
            total_baseline += baseline_dur

    if optimized and optimized.get('conclusion') == 'success':
        optimized_dur = parse_duration(optimized.get('started_at'), optimized.get('completed_at'))
        if optimized_dur:
            total_optimized += optimized_dur

    diff_str = format_diff(baseline_dur, optimized_dur)
    print(f"{job_name:<50} {format_duration(baseline_dur):<12} {format_duration(optimized_dur):<12} {diff_str:<20}")

print("=" * 94)
print(f"{'TOTAL':<50} {format_duration(total_baseline):<12} {format_duration(total_optimized):<12} {format_diff(total_baseline, total_optimized):<20}")
EOF

# Cleanup temp files
rm -f "$BASELINE_FILE" "$OPTIMIZED_FILE"
