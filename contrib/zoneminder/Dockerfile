# ZoneMinder test rig for Thingino cameras.
#
# Ubuntu 24.04 ships ZoneMinder 1.36.33; the images published by the
# ZoneMinder project are from 2021 (ZoneMinder 1.32) and cannot decode
# current H.264/H.265 camera streams. Build from distro packages instead.

FROM docker.io/library/ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive \
    TZ=UTC

# policy-rc.d stops package postinst scripts from trying to start services
# through sysvinit/systemd while the image is being built (no init here).
RUN printf '#!/bin/sh\nexit 101\n' > /usr/sbin/policy-rc.d \
    && chmod 0755 /usr/sbin/policy-rc.d \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
        apache2 \
        ca-certificates \
        curl \
        ffmpeg \
        libapache2-mod-php \
        libdatetime-perl \
        mariadb-client \
        mariadb-server \
        tzdata \
        zoneminder \
    && a2enconf zoneminder \
    && a2enmod rewrite cgi \
    && rm -rf /var/lib/apt/lists/*

# The worker processes run as www-data, so the config has to be group-readable.
# The upstream package leaves it root:root 0640. The packaged
# ZM_PATH_FFMPEG is a CMake "not found" placeholder; pin the real binary.
RUN chown root:www-data /etc/zm/zm.conf \
    && chmod 0640 /etc/zm/zm.conf \
    && printf 'ZM_PATH_FFMPEG=/usr/bin/ffmpeg\n' > /etc/zm/conf.d/99-thingino.conf

# PTZ: ZM's ONVIF module sends a SOAP body with no XML declaration, which
# Thingino's ONVIF parser rejects. Add the declaration at build time.
COPY onvif-declare-xml.pl /tmp/onvif-declare-xml.pl
RUN perl /tmp/onvif-declare-xml.pl && rm /tmp/onvif-declare-xml.pl

# The Debian package ships the CakePHP API without its webroot rewrite rules,
# so /zm/api/<route> 404s. Restore them (AllowOverride is already enabled).
RUN printf '%s\n' \
        '<IfModule mod_rewrite.c>' \
        '    RewriteEngine On' \
        '    RewriteCond %{REQUEST_FILENAME} !-d' \
        '    RewriteCond %{REQUEST_FILENAME} !-f' \
        '    RewriteRule ^ index.php [L]' \
        '</IfModule>' \
        > /usr/share/zoneminder/www/api/.htaccess

RUN mkdir -p /var/log/zm /var/cache/zoneminder/events \
        /var/cache/zoneminder/images /var/cache/zoneminder/temp \
    && chown -R www-data:www-data /var/log/zm /var/cache/zoneminder

VOLUME ["/var/cache/zoneminder/events", "/var/cache/zoneminder/images", "/var/lib/mysql", "/var/log/zm"]

EXPOSE 80

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod 0755 /usr/local/bin/entrypoint.sh

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
