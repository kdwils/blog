FROM nginx:alpine

WORKDIR /src

RUN apk add hugo

COPY . .

ENV HUGO_ENV production
RUN hugo

COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY ./public /usr/share/nginx/html

EXPOSE 8080

CMD ["nginx", "-g", "daemon off;"]