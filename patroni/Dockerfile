FROM postgres:17

RUN apt-get update \
 && apt-get install -y --no-install-recommends python3 python3-venv curl ca-certificates \
 && rm -rf /var/lib/apt/lists/* \
 && python3 -m venv /opt/patroni \
 && /opt/patroni/bin/pip install --no-cache-dir "patroni[etcd3]==4.1.5" "psycopg[binary]==3.3.6"

COPY patroni.yml /etc/patroni/patroni.yml
COPY entrypoint.sh /entrypoint.sh
COPY post_bootstrap.sh /post_bootstrap.sh
RUN chmod +x /entrypoint.sh /post_bootstrap.sh

EXPOSE 5432 8008
ENTRYPOINT ["/entrypoint.sh"]
