# Node 20 is EOL; Vite 8 requires ^20.19 || >=22.12. Node 24 is the current LTS.
FROM node:24-alpine AS builder

WORKDIR /app
COPY package*.json ./
RUN npm install

COPY . .

# Vite inlines VITE_* variables at build time, so this must be a build arg
# rather than a runtime env var. Empty default = same-origin (ALB) routing.
ARG VITE_API_URL=""
ENV VITE_API_URL=$VITE_API_URL

RUN npm run build

# Use nginx to serve static files
FROM nginx:alpine

# Copy built files
COPY --from=builder /app/dist /usr/share/nginx/html

# Copy nginx configuration (no proxy — the ALB handles API routing)
COPY nginx.conf /etc/nginx/conf.d/default.conf

EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
