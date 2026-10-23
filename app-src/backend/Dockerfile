FROM node:18-alpine AS builder
WORKDIR /app
COPY package*.json ./
# npm ci exige package-lock.json (incluido en el repo); --omit=dev reemplaza al obsoleto --only=production
RUN npm ci --omit=dev

FROM node:18-alpine
WORKDIR /app
COPY --from=builder /app/node_modules ./node_modules
COPY server.js ./
USER node
EXPOSE 5678
CMD ["node", "server.js"]
