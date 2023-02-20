FROM alpine:latest as builder

RUN apk add hugo

WORKDIR /src
COPY . .
RUN hugo
RUN ls -l

FROM nginx:alpine

COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=builder /src/public /usr/share/nginx/html
RUN cd /usr/share/nginx/html && ls -l

EXPOSE 8080

CMD ["nginx", "-g", "daemon off;"]