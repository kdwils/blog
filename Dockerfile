FROM alpine:latest as builder

RUN apk add --no-cache hugo
WORKDIR /src
COPY . .

RUN hugo

FROM nginx:stable-alpine

COPY --from=builder /src/public /usr/share/nginx/html

RUN rm /etc/nginx/conf.d/default.conf
COPY nginx/config/app.conf /etc/nginx/conf.d/default.conf

EXPOSE 8080