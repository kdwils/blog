FROM alpine:latest as builder

RUN apk add --update hugo

WORKDIR /src
COPY . .
ENV HUGO_ENV production
RUN hugo

FROM imacatlol/hugo-nginx

COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=builder /src/public /usr/share/nginx/html

EXPOSE 8080