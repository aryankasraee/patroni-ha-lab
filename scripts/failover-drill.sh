#!/usr/bin/env bash
# Kill the primary while a client is writing, and measure what the client sees.
#
# Measures:
#   * write unavailability: time between the last acknowledged write before the
#     kill and the first acknowledged write after it
#   * data loss: acknowledged writes missing on the new primary (expected: 0,
#     because the cluster runs synchronous replication)
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/lib.sh

PGURL="postgresql://app:lab-app@haproxy:5000/lab"
mkdir -p results

wait_healthy
old=$(leader)
echo "leader before: $old"

docker compose exec -T client psql "$PGURL" -v ON_ERROR_STOP=1 -qc \
  "DROP TABLE IF EXISTS events; CREATE TABLE events (n int PRIMARY KEY, ts timestamptz DEFAULT now());"

# Writer runs inside the client container, one insert at a time, and appends
# "<n> <epoch-ms>" to a log only after the insert was acknowledged.
docker compose exec -T client rm -f /tmp/acked.log
docker compose exec -d client bash -c '
  i=0
  while true; do
    i=$((i+1))
    if psql "'"$PGURL"'" -qtAc "INSERT INTO events(n) VALUES ($i)" >/dev/null 2>&1; then
      echo "$i $(date +%s%3N)" >> /tmp/acked.log
    else
      i=$((i-1))
    fi
    sleep 0.05
  done'

sleep 5
before=$(docker compose exec -T client sh -c 'wc -l < /tmp/acked.log' | tr -d '[:space:]')
echo "writes acknowledged before kill: $before"

# Same clock as the writer (the client container), not the host: the Docker VM
# clock can differ from the host clock by seconds.
t_kill=$(docker compose exec -T client date +%s%3N)
docker kill "$(docker compose ps -q "$old")" >/dev/null
echo "killed $old at t=$t_kill"

# wait for a new leader and for writes to resume
deadline=$((SECONDS+90))
while (( SECONDS < deadline )); do
  new=$(leader 2>/dev/null || true)
  if [[ -n "$new" && "$new" != "$old" ]]; then break; fi
  sleep 1
done
[[ -n "${new:-}" && "$new" != "$old" ]] || { echo "no new leader elected" >&2; exit 1; }
echo "leader after: $new"
sleep 8   # let the writer produce acknowledged writes on the new primary

docker compose exec -T client sh -c 'cat /tmp/acked.log' > results/acked.log
docker compose exec -T client pkill -f "INSERT INTO events" >/dev/null 2>&1 || true
docker compose exec -T client sh -c 'pkill -f "while true" || true' >/dev/null 2>&1 || true

python3 - "$t_kill" "$old" "$new" <<'PY'
import sys, json
t_kill, old, new = int(sys.argv[1]), sys.argv[2], sys.argv[3]
rows = [tuple(map(int, l.split())) for l in open("results/acked.log") if l.strip()]
before = [r for r in rows if r[1] <= t_kill]
after = [r for r in rows if r[1] > t_kill]
assert before and after, "writer produced no writes on one side of the kill"
# Unavailability = largest silence between two consecutive acknowledged writes.
gap_ms = max(b[1] - a[1] for a, b in zip(rows, rows[1:]))
json.dump({"old_leader": old, "new_leader": new, "acked_total": len(rows),
           "acked_before_kill": len(before), "acked_after_kill": len(after),
           "write_unavailable_ms": gap_ms,
           "acked_ids": [r[0] for r in rows]}, open("results/_drill.json", "w"))
print(f"write unavailability (largest gap between acknowledged writes): {gap_ms} ms")
PY

# Bring the old primary back: it must rejoin as a replica (pg_rewind if it diverged).
docker compose start "$old" >/dev/null
echo "restarted $old, waiting for it to rejoin"
