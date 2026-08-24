# syntax=docker/dockerfile:1
# --- Build stage: all deps so the build (if any) can run ---
FROM node:20-alpine AS builder
RUN apk add --no-cache git
WORKDIR /app
# COPY all files except those excluded (including .git) to keep lefthook happy
COPY . .
# Strip prepare script instead of the wrong `npm set-script`
RUN npm pkg delete scripts.prepare >/dev/null 2>&1 || true
RUN npm install --legacy-peer-deps
# Prisma: generate the client BEFORE build (no-op without a schema).
RUN if [ -f prisma/schema.prisma ] || [ -f schema.prisma ]; then \
      npx --yes prisma generate; \
    fi
# Auto-build when the app defines a build script (Next.js needs it).
# Fails the image build if the script exists and errors — surfaces bugs early.
RUN if node -e "process.exit(require('./package.json').scripts?.build ? 0 : 1)"; then \
      npm run build; \
    else \
      echo "no build script — skipping"; \
    fi

# --- Runtime: non-root built-in `node` user ---
FROM node:20-alpine AS runner
ENV NODE_ENV=production
WORKDIR /app
# Copy the built app WITH its node_modules from the builder (avoids a second
# install and guarantees framework binaries + build output are present).
COPY --from=builder /app .
USER node
EXPOSE 3000
# Fixed CMD to launch common Next.js production server entrypoint
CMD ["sh", "-c", "export PATH=/app/node_modules/.bin:$PATH; exec next start"]
