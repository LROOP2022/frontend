# syntax=docker/dockerfile:1

# ---- build ----
FROM node:24.12.0-alpine AS build
WORKDIR /app

COPY package.json package-lock.json ./
RUN npm ci

COPY . .
# build-only: без vue-tsc, чтобы ошибка типов не блокировала деплой на хакатоне.
# Строгая сборка: RUN npm run build
RUN npm run build-only

# ---- runtime ----
# unprivileged-образ: работает не от root, пишет только в /tmp
FROM nginxinc/nginx-unprivileged:1.28-alpine
COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=build /app/dist /usr/share/nginx/html

EXPOSE 3000
HEALTHCHECK --interval=30s --timeout=3s CMD wget -q -O /dev/null http://127.0.0.1:3000/healthz || exit 1
