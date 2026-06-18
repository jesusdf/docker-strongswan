#
# StrongSwan VPN + Alpine Linux
#

FROM alpine:3.24

RUN apk --update add ca-certificates \
            curl \
            curl-dev \
            ip6tables \
            iproute2 \
            iptables-dev \
            iptables-legacy \
            openssl \
            strongswan \
            xl2tpd \
            ppp \
            openrc \
            bash \
            tzdata \
    && rm -rf /var/cache/apk/* \
    && rm -f  /sbin/apk \
              /usr/bin/wget \
              /usr/sbin/sendmail \
              /usr/bin/nc

EXPOSE 500/udp \
       4500/udp

HEALTHCHECK --interval=30s --timeout=10s --start-period=15s --retries=3 \
    CMD swanctl --stats > /dev/null 2>&1

COPY startup.sh /
RUN chmod +x /startup.sh

ENTRYPOINT ["/startup.sh"]