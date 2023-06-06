FROM nginx:alpine

RUN apk add hugo

WORKDIR /src
COPY . .
ENV HUGO_ENV production
RUN hugo

COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY /src/public /usr/share/nginx/html

EXPOSE 8080

CMD ["nginx", "-g", "daemon off;"]