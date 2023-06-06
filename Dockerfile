FROM alpine:latest as builder

RUN apk add --update hugo

WORKDIR /src
COPY . .
ENV HUGO_ENV production
RUN hugo

FROM nginx:alpine

RUN chown nginx:nginx /usr/share/nginx/*

COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=builder /src/public /usr/share/nginx/blog

EXPOSE 8080