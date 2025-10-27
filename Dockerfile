FROM alpine:latest AS builder

ARG HUGO_VERSION=0.151.0
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

FROM nginx:1.29.1-alpine-slim

COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=builder /src/public /usr/share/nginx/html

EXPOSE 8080

CMD ["nginx", "-g", "daemon off;"]