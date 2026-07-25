# Matches the infra repo's expected static-app pattern (terraform/README.md):
# vite build in node:22-alpine, served by nginx on :80, health = GET / (200).
FROM node:22-alpine AS build
WORKDIR /app
COPY package.json ./
RUN npm install
COPY . .
RUN npm run build

FROM nginx:alpine
COPY --from=build /app/dist /usr/share/nginx/html
# SPA fallback: route everything to index.html
RUN printf 'server { listen 80; root /usr/share/nginx/html; location / { try_files $uri /index.html; } }' \
  > /etc/nginx/conf.d/default.conf
