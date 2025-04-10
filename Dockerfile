FROM alpine:latest AS builder

RUN apk add --update hugo

WORKDIR /src
COPY . .
ENV HUGO_ENV=production
RUN hugo

FROM nginx:1.27.4-alpine-slim

COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=builder /src/public /usr/share/nginx/html

EXPOSE 8080

CMD ["nginx", "-g", "daemon off;"]