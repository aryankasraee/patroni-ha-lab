#!/usr/bin/env bash
# Take a base backup from a replica, restore it into a throwaway container, and
# compare row counts. A backup you have not restored is a hope, not a backup.
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/lib.sh

PRIMARY="postgresql://app:lab-app@haproxy:5000/lab"
REPLICA_HOST=haproxy
wait_healthy 180

docker compose exec -T client psql "$PRIMARY" -qc \
  "CREATE TABLE IF NOT EXISTS backup_probe (n int PRIMARY KEY); INSERT INTO backup_probe SELECT g FROM generate_series(1,1000) g ON CONFLICT DO NOTHING;"
expected=$(docker compose exec -T client psql "$PRIMARY" -qtAc "SELECT count(*) FROM backup_probe" | tr -d '[:space:]')

docker volume rm -f patroni-lab-restore >/dev/null
docker compose exec -T client rm -rf /results/basebackup
# Backup is read from the replica endpoint (port 5001): no load on the primary.
docker compose exec -T -e PGPASSWORD=lab-replicator client \
  pg_basebackup -h "$REPLICA_HOST" -p 5001 -U replicator -D /results/basebackup -Fp -X stream -c fast
echo "base backup taken from a replica"

docker volume create patroni-lab-restore >/dev/null
docker run --rm -v patroni-lab-restore:/restore -v "$PWD/results/basebackup:/src:ro" postgres:17 \
  bash -c 'cp -a /src/. /restore/ && rm -f /restore/standby.signal /restore/recovery.signal && chown -R postgres:postgres /restore && chmod 700 /restore'
# Files are owned by the container user on Linux hosts, so clean up from inside.
docker compose exec -T client rm -rf /results/basebackup

docker rm -f patroni-lab-restore-test >/dev/null 2>&1 || true
docker run -d --name patroni-lab-restore-test -v patroni-lab-restore:/var/lib/postgresql/data postgres:17 \
  postgres -c hot_standby=off -c listen_addresses=localhost \
    -c hba_file=/var/lib/postgresql/data/pg_hba.conf \
    -c ident_file=/var/lib/postgresql/data/pg_ident.conf >/dev/null
# Patroni writes absolute file paths into postgresql.conf (its data dir is
# .../data/pgdata). Restoring the same files elsewhere needs those overridden,
# which is why the restore drill exists: this only shows up when you restore.
for _ in $(seq 1 30); do
  docker exec patroni-lab-restore-test pg_isready -q -h 127.0.0.1 && break; sleep 1
done
restored=$(docker exec -e PGPASSWORD=lab-superuser patroni-lab-restore-test psql -h 127.0.0.1 -U postgres -d lab -qtAc "SELECT count(*) FROM backup_probe" | tr -d '[:space:]')
docker rm -f patroni-lab-restore-test >/dev/null; docker volume rm patroni-lab-restore >/dev/null

echo "rows expected=$expected restored=$restored"
[[ "$expected" == "$restored" ]] || { echo "RESTORE MISMATCH" >&2; exit 1; }
echo "restore verified"
