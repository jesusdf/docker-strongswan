#
# StrongSwan VPN + Alpine Linux
#

FROM alpine:3.17.2

RUN apk --update add ca-certificates \
            curl \
            curl-dev \
            ip6tables \
            iproute2 \
            iptables-dev \
            openssl \
            strongswan && \
            xl2tpd && \
    rm -rf /var/cache/apk/*

EXPOSE 500/udp \
       4500/udp

ENTRYPOINT ["/usr/sbin/ipsec"]
CMD ["start", "--nofork"]
