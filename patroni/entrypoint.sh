#!/bin/sh
set -e
mkdir -p /var/lib/postgresql/data
chown -R postgres:postgres /var/lib/postgresql/data
chmod 700 /var/lib/postgresql/data
# post_bootstrap must be runnable by the postgres user

exec gosu postgres /opt/patroni/bin/patroni /etc/patroni/patroni.yml
