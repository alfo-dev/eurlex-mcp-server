FROM node:22-alpine AS builder

RUN apk upgrade --no-cache zlib
RUN corepack enable pnpm
WORKDIR /app
ENV HUSKY=0
COPY package.json pnpm-lock.yaml ./
RUN pnpm install --frozen-lockfile
COPY tsconfig.json ./
COPY src/ ./src/
RUN pnpm run build
# Separate, clean prod-only install into a dedicated directory
RUN mkdir /prod_modules && \
    cp package.json pnpm-lock.yaml /prod_modules/ && \
    cd /prod_modules && \
    pnpm install --frozen-lockfile --prod --ignore-scripts

FROM node:22-alpine

RUN apk upgrade --no-cache zlib
RUN rm -rf /usr/local/lib/node_modules/npm \
    && rm -f /usr/local/bin/npm /usr/local/bin/npx
WORKDIR /app
ENV HUSKY=0
COPY --from=builder /prod_modules/node_modules/ ./node_modules/
COPY --from=builder /app/dist/ ./dist/

EXPOSE 3001
USER node

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD wget --no-verbose --tries=1 --spider http://localhost:3001/health || exit 1

CMD ["node", "dist/http.js"]
