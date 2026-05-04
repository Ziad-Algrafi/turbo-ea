# ---------------------------------------------------------------------------
# Stage 1: Build backend Python dependencies
# ---------------------------------------------------------------------------
FROM python:3.12-alpine AS backend-build

RUN apk add --no-cache gcc musl-dev libpq-dev

WORKDIR /app

COPY backend/pyproject.toml ./
RUN mkdir -p app && touch app/__init__.py && \
    pip install --no-cache-dir --prefix=/install . && \
    rm -rf app

COPY VERSION ./VERSION
COPY backend/ ./
RUN pip install --no-cache-dir --no-deps --prefix=/install .

# ---------------------------------------------------------------------------
# Stage 2: Build frontend
# ---------------------------------------------------------------------------
FROM node:20-alpine AS frontend-build

WORKDIR /app
COPY frontend/package.json frontend/package-lock.json frontend/xlsx-0.20.3.tgz ./
RUN npm ci
COPY VERSION ./VERSION
COPY frontend/ ./
RUN npm run build

# ---------------------------------------------------------------------------
# Stage 3: Clone DrawIO
# ---------------------------------------------------------------------------
FROM alpine/git:v2.47.2 AS drawio
RUN git clone --depth 1 --branch v26.0.9 https://github.com/jgraph/drawio.git /drawio

# ---------------------------------------------------------------------------
# Stage 4: Production — single container with backend + nginx
# ---------------------------------------------------------------------------
FROM python:3.12-alpine AS production

RUN apk add --no-cache nginx libpq supervisor && rm -rf /var/cache/apk/*

WORKDIR /app

# Backend
COPY --from=backend-build /install /usr/local
COPY --from=backend-build /app/VERSION ./VERSION
COPY --from=backend-build /app/app ./app
COPY --from=backend-build /app/alembic ./alembic
COPY --from=backend-build /app/alembic.ini ./alembic.ini

# Frontend
COPY --from=frontend-build /app/dist /usr/share/nginx/html

# DrawIO
COPY --from=drawio /drawio/src/main/webapp /usr/share/nginx/drawio
COPY frontend/drawio-config/PreConfig.js /usr/share/nginx/drawio/js/PreConfig.js
COPY frontend/drawio-config/PostConfig.js /usr/share/nginx/drawio/js/PostConfig.js

RUN sed -i \
    -e '/<link rel="manifest"/d' \
    -e '/serviceWorker/d' \
    -e 's/<head>/<head><!--email_off-->/' \
    /usr/share/nginx/drawio/index.html

# Nginx + supervisord configs
COPY dokploy/nginx.conf /etc/nginx/http.d/default.conf
COPY dokploy/supervisord.conf /etc/supervisor.d/turbo-ea.ini
COPY dokploy/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Nginx dirs
RUN mkdir -p /run/nginx && \
    chown -R nginx:nginx /usr/share/nginx/html /usr/share/nginx/drawio /var/lib/nginx && \
    rm -f /etc/nginx/http.d/default.conf.bak

EXPOSE 80

HEALTHCHECK --interval=30s --timeout=5s --start-period=60s --retries=3 \
    CMD wget -qO- http://localhost:80/api/health || exit 1

ENTRYPOINT ["/entrypoint.sh"]
