FROM php:5.6-apache
RUN apt-get update && \
    apt-get install -y libfreetype6-dev libjpeg62-turbo-dev && \
    docker-php-ext-install mysqli && \
    docker-php-ext-install mbstring && \
    docker-php-ext-configure gd --with-freetype-dir=/usr/include/ --with-jpeg-dir=/usr/include/  &&  \
    docker-php-ext-install gd

RUN  sed -i "s|80|8080|g" /etc/apache2/ports.conf 
RUN  sed -i "s|443|8443|g" /etc/apache2/ports.conf 
COPY index.php /var/www/html
COPY image.php /var/www/html
COPY dist /var/www/html/dist
COPY components /var/www/html/components
RUN chmod 777 -R /var /etc
EXPOSE 8080 8443
