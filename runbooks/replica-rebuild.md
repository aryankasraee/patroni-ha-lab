# Runbook: rebuild a broken or lagging replica

Symptoms: a member stays `stopped`, `start failed`, or falls further and further
behind (`Lag` grows in `patronictl list`).

```bash
docker compose exec -T patroni2 /opt/patroni/bin/patronictl -c /etc/patroni/patroni.yml list
```

## 1. Rule out the cheap causes

- Is the member actually running? `docker compose ps`
- Is the disk full? A replica that cannot write WAL stops replicating.
- Is it only slow? A growing lag with a healthy state may just be a long-running
  query on the replica holding back replay.

## 2. Reinitialize

Never reinitialize the leader. Check the member's `Role` first.

```bash
docker compose exec -T patroni2 /opt/patroni/bin/patronictl -c /etc/patroni/patroni.yml \
  reinit lab <member> --force
```

Patroni wipes the member's data directory and re-clones it from the leader.

## 3. Verify

```bash
docker compose exec -T patroni2 /opt/patroni/bin/patronictl -c /etc/patroni/patroni.yml list
```

Done when the member is `streaming` with `Lag: 0`, and the cluster again has a
synchronous standby.

## Notes

- A large database makes `reinit` long and puts read load on the leader. Prefer a
  base backup from another replica when you can (see `scripts/backup-restore-drill.sh`).
