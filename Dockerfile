FROM alpine:latest AS builder

RUN apk add --no-cache wget

RUN wget -O /tmp/hugo.tar.gz https://github.com/gohugoio/hugo/releases/download/v0.148.2/hugo_0.148.2_linux-amd64.tar.gz && \
    tar -xf /tmp/hugo.tar.gz -C /usr/local/bin/ && \
    rm /tmp/hugo.tar.gz

WORKDIR /src
COPY . .
ENV HUGO_ENV=production
RUN hugo --minify

FROM nginx:1.29.1-alpine-slim

COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=builder /src/public /usr/share/nginx/html

EXPOSE 8080

CMD ["nginx", "-g", "daemon off;"]