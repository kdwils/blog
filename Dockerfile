FROM alpine:latest as builder

RUN apk add --no-cache hugo

WORKDIR /src
COPY . /src

RUN hugo

FROM nginx:alpine

COPY nginx/default.conf /etc/nginx/conf.d/default.conf
COPY --from=builder /src/public /usr/share/nginx/html

EXPOSE 8080
CMD ["nginx", "-g", "daemon off;"]