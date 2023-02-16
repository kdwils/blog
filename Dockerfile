FROM alpine:latest as builder

RUN apk add --no-cache hugo
WORKDIR /src
COPY . .

RUN hugo

FROM nginx:alpine

COPY --from=builder /src/public /usr/share/nginx/html

EXPOSE 80