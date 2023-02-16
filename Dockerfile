FROM alpine:latest as builder

RUN apk add --no-cache hugo
WORKDIR /src
COPY . .

RUN hugo

FROM nginx:stable-alpine

COPY --from=build /src/public /usr/share/nginx/html

EXPOSE 80 443