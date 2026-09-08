FROM alpine:latest AS builder

ARG HUGO_VERSION=0.165.0
ARG TARGETARCH

RUN apk add --no-cache ca-certificates && \
    ARCH=${TARGETARCH:-amd64} && \
    wget -O hugo.tar.gz "https://github.com/gohugoio/hugo/releases/download/v${HUGO_VERSION}/hugo_${HUGO_VERSION}_linux-${ARCH}.tar.gz" && \
    tar -xzf hugo.tar.gz hugo && \
    mv hugo /usr/local/bin/ && \
    rm hugo.tar.gz

WORKDIR /src
COPY . .
ENV HUGO_ENV=production
RUN hugo --minify

FROM caddy:2-alpine AS caddy

FROM gcr.io/distroless/static-debian12

COPY --from=caddy /usr/bin/caddy /usr/bin/caddy
COPY Caddyfile /etc/caddy/Caddyfile
COPY --from=builder /src/public /usr/share/caddy

EXPOSE 8080

ENTRYPOINT ["/usr/bin/caddy", "run", "--config", "/etc/caddy/Caddyfile", "--adapter", "caddyfile"]