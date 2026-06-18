#!/bin/bash

cp /usr/share/zoneinfo/${TZ} /etc/localtime
echo "${TZ}" > /etc/timezone

touch /run/xtables.lock

# Using L2TP?
if [ -f /etc/ppp/options.l2tpd.client ]; then
    /usr/lib/strongswan/charon &
    sleep 5
    swanctl --load-all
    swanctl --list-conns
    CNAME=$(swanctl --list-conns | head -n1 | cut -d: -f1 | xargs)
    (sleep 7 && echo "c $CNAME" > /var/run/xl2tpd/l2tp-control) &
    exec /usr/sbin/xl2tpd -D
else
    (sleep 5 && swanctl --load-all && swanctl --list-conns) &
    exec /usr/lib/strongswan/charon
fi
