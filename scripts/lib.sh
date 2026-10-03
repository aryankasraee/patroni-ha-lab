#!/usr/bin/env bash
# Shared helpers for the lab scripts.
set -euo pipefail

cluster_json() {
  for port in 8008 8009 8010; do
    out=$(curl -fsS --max-time 2 "http://localhost:${port}/cluster" 2>/dev/null) && { echo "$out"; return 0; }
  done
  return 1
}

leader() {
  cluster_json | python3 -c 'import sys,json; print(next((m["name"] for m in json.load(sys.stdin)["members"] if m["role"] in ("leader","master")),""))'
}

# healthy = one leader and two running replicas, one of them synchronous
wait_healthy() {
  local timeout=${1:-180} start=$SECONDS
  while (( SECONDS - start < timeout )); do
    if out=$(cluster_json 2>/dev/null) && python3 - "$out" <<'PY'
import sys, json
m = json.loads(sys.argv[1])["members"]
leaders = [x for x in m if x["role"] in ("leader", "master") and x["state"] == "running"]
syncs = [x for x in m if x["role"] == "sync_standby" and x["state"] == "streaming"]
sys.exit(0 if len(m) == 3 and len(leaders) == 1 and len(syncs) >= 1 else 1)
PY
    then return 0; fi
    sleep 2
  done
  echo "cluster did not become healthy within ${timeout}s" >&2
  docker compose logs --tail=5 patroni1 patroni2 patroni3 >&2 || true
  return 1
}

now_ms() { python3 -c 'import time; print(int(time.time()*1000))'; }
