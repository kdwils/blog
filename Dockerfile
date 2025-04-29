FROM alpine:latest AS builder

RUN apk add --no-cache wget

RUN wget -O /tmp/hugo.tar.gz https://github.com/gohugoio/hugo/releases/download/v0.146.1/hugo_0.146.1_linux-amd64.tar.gz && \
    tar -xf /tmp/hugo.tar.gz -C /usr/local/bin/ && \
    rm /tmp/hugo.tar.gz

WORKDIR /src
COPY . .
ENV HUGO_ENV=production
RUN hugo

FROM nginx:1.27.5-alpine-slim

COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=builder /src/public /usr/share/nginx/html

EXPOSE 8080

CMD ["nginx", "-g", "daemon off;"]