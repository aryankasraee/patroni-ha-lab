#!/bin/sh
# Runs once on the first primary, right after initdb.
set -e
psql -v ON_ERROR_STOP=1 -d postgres <<SQL
CREATE ROLE app LOGIN PASSWORD '${APP_PASSWORD}';
CREATE DATABASE lab OWNER app;
SQL
