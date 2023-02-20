FROM alpine:latest as builder

RUN apk add hugo

WORKDIR /src
COPY . .
RUN hugo

FROM nginx:alpine

COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=builder /src/public /usr/share/nginx/html

EXPOSE 8080

CMD ["nginx", "-g", "daemon off;"]