# Node 20 is EOL; Vite 8 requires ^20.19 || >=22.12. Node 24 is the current LTS.
#
# Pinned to BUILDPLATFORM: the build output is architecture-independent static
# assets, so there is no reason to run npm under emulation for each platform.
FROM --platform=$BUILDPLATFORM node:24-alpine AS builder

WORKDIR /app
COPY package*.json ./
RUN npm install

COPY . .

# Vite inlines VITE_* variables at build time, so this must be a build arg
# rather than a runtime env var. Empty default = same-origin (ALB) routing.
ARG VITE_API_URL=""
ENV VITE_API_URL=$VITE_API_URL

RUN npm run build

# Use nginx to serve static files.
# The unprivileged variant runs as uid 101 and listens on 8080 — the stock
# nginx image needs root to bind port 80.
FROM nginxinc/nginx-unprivileged:alpine

# Copy built files
COPY --from=builder /app/dist /usr/share/nginx/html

# Copy nginx configuration (no proxy — the ALB handles API routing)
COPY nginx.conf /etc/nginx/conf.d/default.conf

USER 101

EXPOSE 8080
CMD ["nginx", "-g", "daemon off;"]
