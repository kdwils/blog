FROM alpine:latest as builder

RUN apk add hugo

WORKDIR /src
COPY . .
ENV HUGO_ENV production
RUN hugo

FROM nginx:alpine

RUN rm /usr/share/nginx/html/index.html

COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=builder /src/public /usr/share/nginx/html

EXPOSE 8080

CMD ["nginx", "-g", "daemon off;"]