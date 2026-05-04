#!/bin/sh
set -e

PGDATA="/var/lib/postgresql/data"
PGUSER="turboea"
PGDB="turboea"

if [ ! -d "$PGDATA/base" ]; then
    echo "Initializing PostgreSQL database..."
    mkdir -p "$PGDATA"
    chown -R postgres:postgres /var/lib/postgresql

    su-exec postgres pg_ctl initdb -D "$PGDATA" -o "--auth-host=trust --auth-local=trust"

    echo "host all  all  127.0.0.1/32  trust" >> "$PGDATA/pg_hba.conf"
    echo "local all  all  trust" >> "$PGDATA/pg_hba.conf"

    su-exec postgres pg_ctl -D "$PGDATA" -o "-p 5432" -w start

    su-exec postgres psql -p 5432 -c "CREATE USER $PGUSER WITH CREATEDB;" 2>/dev/null || true
    su-exec postgres psql -p 5432 -c "CREATE DATABASE $PGDB OWNER $PGUSER;" 2>/dev/null || true

    su-exec postgres pg_ctl -D "$PGDATA" -m fast -w stop

    echo "PostgreSQL initialized."
else
    echo "PostgreSQL data directory found, skipping init."
fi

export POSTGRES_HOST=127.0.0.1
export POSTGRES_PORT=5432
export POSTGRES_DB=$PGDB
export POSTGRES_USER=$PGUSER

echo "Waiting for PostgreSQL to accept connections..."
max_attempts=30
attempt=0
su-exec postgres pg_ctl -D "$PGDATA" -o "-p 5432" -w start
while [ $attempt -lt $max_attempts ]; do
    if su-exec postgres psql -p 5432 -c "SELECT 1" > /dev/null 2>&1; then
        echo "PostgreSQL is ready."
        break
    fi
    attempt=$((attempt + 1))
    echo "  attempt $attempt/$max_attempts..."
    sleep 1
done
su-exec postgres pg_ctl -D "$PGDATA" -m fast -w stop

exec supervisord -c /etc/supervisord.conf
