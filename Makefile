.PHONY: up down drill backup status clean
up:
	docker compose up -d --build
	@bash -c 'source scripts/lib.sh; wait_healthy 240 && echo cluster healthy'
status:
	@curl -s localhost:8008/cluster | python3 -m json.tool | grep -E '"(name|role|state|lag)"'
drill:
	scripts/failover-drill.sh
	scripts/verify-no-loss.sh
backup:
	scripts/backup-restore-drill.sh
down:
	docker compose down -v
clean: down
	rm -rf results/*.json results/*.log
