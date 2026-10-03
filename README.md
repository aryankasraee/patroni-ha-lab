# patroni-ha-lab

A three-node PostgreSQL high-availability cluster you can start with one command,
break on purpose, and measure. It exists to answer two questions with evidence
instead of confidence:

1. **What does a client actually see when the primary dies?**
2. **Can I restore from the backup I think I have?**

```
                    ┌──────────┐
 client ──────────▶ │ HAProxy  │  :5000 read/write → whichever node answers 200 on /primary
                    │          │  :5001 read-only  → nodes answering 200 on /replica
                    └────┬─────┘
          ┌──────────────┼──────────────┐
     ┌────▼────┐    ┌────▼────┐    ┌────▼────┐
     │patroni1 │    │patroni2 │    │patroni3 │   PostgreSQL 17 + Patroni 4.1.5
     └────┬────┘    └────┬────┘    └────┬────┘
          └──────────────┼──────────────┘
                     ┌───▼───┐
                     │ etcd  │   leader lock / cluster state (single member: lab only)
                     └───────┘
```

## Run it

```bash
make up        # build, start, wait until 1 leader + a synchronous standby
make drill     # kill the primary under write load, measure, verify nothing was lost
make backup    # base backup from a replica → restore into a throwaway container → compare
make down
```

Requires Docker with Compose v2, `curl`, and `python3` on the host.

## What the failover drill does

`scripts/failover-drill.sh` runs a writer inside the network that inserts one
numbered row at a time and records a row in a log **only after the database
acknowledged it**. It then `docker kill`s the current primary and keeps writing.
Afterwards `scripts/verify-no-loss.sh` checks that every acknowledged row exists
on the new primary, and the old primary is started again to prove it rejoins as a
replica.

Result of a run on Docker Desktop (macOS, a laptop, so treat it as a shape, not a
benchmark):

| Measurement | Value |
|---|---|
| Largest gap between two acknowledged writes | 17,045 ms |
| Acknowledged writes lost | 0 |
| Old primary rejoined as replica | yes |

CI runs the same drill on every push and publishes its own numbers in the job
summary, so you can compare.

### Why ~17 seconds

It is mostly configuration, not a limit. Patroni will not promote anyone until the
old leader's lock expires: `ttl: 15`, plus HAProxy noticing (`inter 1s fall 2`).
Lowering `ttl`/`loop_wait` shortens failover and raises the chance of a needless
failover on a slow network or a long GC pause. That is a decision to make against
your own latency budget, which is why it lives in `patroni/patroni.yml` with a
comment, not in the code.

### Why nothing is lost

`synchronous_mode: true` with `synchronous_node_count: 1`: a commit is
acknowledged only after one replica has it, and Patroni only promotes a replica
that was synchronous. The price is that writes block if every standby is gone.
Turn it off and the drill will tell you what you now risk.

## What the backup drill does

`scripts/backup-restore-drill.sh` takes a `pg_basebackup` **from a replica** (no
load on the primary), restores it into a clean volume, starts a throwaway
PostgreSQL on it and compares row counts with the source.

It earns its place: the first restore failed. Patroni writes absolute paths
(`hba_file`, `ident_file`) into `postgresql.conf` under its own data directory, so
a restore into any other path will not start until they are overridden. You only
find that out by restoring.

## Runbooks

- [`runbooks/failover.md`](runbooks/failover.md): planned switchover and what to check after an unplanned one
- [`runbooks/replica-rebuild.md`](runbooks/replica-rebuild.md): reinitialize a broken or lagging replica

## Deliberately out of scope

This is a lab. A production setup also needs:

- a three-member etcd (one member is a single point of failure here)
- TLS between nodes and clients, and secrets outside the compose file
- continuous WAL archiving for point-in-time recovery (this lab proves a base
  backup restores, not that you can restore to 14:03 yesterday)
- monitoring and alerting on replication lag and leader changes

## License

MIT
