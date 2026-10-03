#!/usr/bin/env bash
# Every write the client saw acknowledged must exist on the current primary.
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/lib.sh

PGURL="postgresql://app:lab-app@haproxy:5000/lab"
wait_healthy 240
python3 - <<'PY' > results/_ids.txt
import json; print("\n".join(map(str, json.load(open("results/_drill.json"))["acked_ids"])))
PY
present=$(docker compose exec -T client psql "$PGURL" -qtAc "SELECT n FROM events ORDER BY n" | sort -n)
missing=$(comm -23 <(sort -n results/_ids.txt) <(echo "$present") | wc -l | tr -d ' ')
echo "acknowledged writes missing on the new primary: $missing"

python3 - "$missing" <<'PY'
import sys, json, datetime
d = json.load(open("results/_drill.json")); d.pop("acked_ids")
d["acknowledged_writes_lost"] = int(sys.argv[1])
d["measured_at"] = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
json.dump(d, open("results/failover.json", "w"), indent=2)
print(json.dumps(d, indent=2))
PY
rm -f results/_drill.json results/_ids.txt results/acked.log
[[ "$missing" == "0" ]]
