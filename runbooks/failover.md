# Runbook: failover

## Planned switchover (maintenance on the primary)

Use this instead of killing a node: it waits for the target to catch up, so no
write is lost and the pause is short.

```bash
docker compose exec -T patroni2 /opt/patroni/bin/patronictl -c /etc/patroni/patroni.yml list
docker compose exec -T patroni2 /opt/patroni/bin/patronictl -c /etc/patroni/patroni.yml \
  switchover lab --leader <current-leader> --candidate <replica> --force
```

Expected: the candidate becomes `Leader` on a new timeline; the old leader shows
`stopped` for a few seconds, then `streaming`.

## After an unplanned failover

1. **Who is leader now?** `patronictl list`, or `curl localhost:8008/cluster`.
2. **Is there a synchronous standby again?** With `synchronous_mode: true`, writes
   stall if no standby is available. A cluster with a leader and no sync standby
   is not healthy yet.
3. **Did the old primary come back as a replica?** It should rejoin on its own
   (`pg_rewind` is enabled). If it stays `stopped` or `start failed`, follow
   [replica-rebuild](replica-rebuild.md).
4. **Did clients recover?** Read/write traffic goes through HAProxy `:5000`; check
   `http://localhost:17000` shows exactly one green server in `primary`.
5. **Write down the timeline.** What failed, when, how long writes were
   unavailable. The drill gives you a baseline to compare against.

## Do not

- Run `docker kill` on the leader and call it a switchover. That is a failure
  test, and it costs the full lock TTL.
- Promote a node by hand with `pg_ctl promote`. Patroni will fight you.
