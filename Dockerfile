FROM alpine:latest as builder

RUN apk add --update hugo

WORKDIR /src
COPY . .
ENV HUGO_ENV production
RUN hugo

FROM nginx:alpine

USER root

COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY nginx.conf /etc/nginx/nginx.conf 
COPY --from=builder /src/public /var/www/html

EXPOSE 8080

CMD ["nginx", "-g", "daemon off;"]