#!/bin/sh
set -e

if [ -n "${POSTGRES_HOST}" ]; then
    echo "Waiting for PostgreSQL at ${POSTGRES_HOST}:${POSTGRES_PORT:-5432}..."
    max_attempts=30
    attempt=0
    while [ $attempt -lt $max_attempts ]; do
        if python -c "
import socket, sys
s = socket.socket()
s.settimeout(2)
try:
    s.connect(('${POSTGRES_HOST}', ${POSTGRES_PORT:-5432}))
    s.close()
    sys.exit(0)
except:
    sys.exit(1)
" 2>/dev/null; then
            echo "PostgreSQL is ready."
            break
        fi
        attempt=$((attempt + 1))
        echo "  attempt $attempt/$max_attempts..."
        sleep 2
    done
fi

exec supervisord -c /etc/supervisord.conf
