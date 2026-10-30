# syntax=docker/dockerfile:1.7

FROM node:20.20.2-alpine3.23@sha256:fb4cd12c85ee03686f6af5362a0b0d56d50c58a04632e6c0fb8363f609372293 AS node

FROM node AS base
WORKDIR /app
COPY package.json package-lock.json ./

FROM base AS deps-dev
RUN --mount=type=cache,target=/root/.npm \
    npm ci --no-audit --no-fund

FROM deps-dev AS test
COPY src ./src
COPY test ./test
RUN npm run lint \
 && npm test \
 && touch /tmp/tests-passed

FROM base AS deps-prod
RUN --mount=type=cache,target=/root/.npm \
    npm ci --omit=dev --no-audit --no-fund

FROM alpine:3.23.7@sha256:ff7f0c727dd796aa36787bfcd9a64bf35a6ce72a73451b3359fde849b6703d63 AS runtime
RUN apk add --no-cache libstdc++=15.2.0-r2 libgcc=15.2.0-r2 \
 && addgroup -g 1000 node \
 && adduser -u 1000 -G node -s /bin/sh -D node \
 && rm -f /var/log/apk.log
COPY --from=node /usr/local/bin/node /usr/local/bin/node
ENV NODE_ENV=production \
    PORT=3000
WORKDIR /app

COPY --from=deps-prod /app/node_modules ./node_modules
COPY package.json ./
COPY src ./src
COPY --from=test /tmp/tests-passed /tmp/tests-passed

USER node
EXPOSE 3000

HEALTHCHECK --interval=10s --timeout=3s --start-period=5s --retries=3 \
    CMD ["wget", "-q", "-O", "/dev/null", "http://127.0.0.1:3000/health"]

ARG APP_VERSION=0.0.0-dev
ARG GIT_SHA=unknown
ARG SOURCE_URL=https://gitlab.shop-sas.internal/platform/shopapi
LABEL org.opencontainers.image.title="shopapi" \
      org.opencontainers.image.description="API catalogue produits Shop SAS" \
      org.opencontainers.image.vendor="Shop SAS" \
      org.opencontainers.image.version="${APP_VERSION}" \
      org.opencontainers.image.revision="${GIT_SHA}" \
      org.opencontainers.image.source="${SOURCE_URL}" \
      org.opencontainers.image.base.name="docker.io/library/alpine:3.23.7"
ENV APP_VERSION=${APP_VERSION}

CMD ["node", "src/server.js"]
