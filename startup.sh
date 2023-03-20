
#!/bin/bash

# Using L2TP?
if [ -f /etc/ppp/options.l2tpd.client ]; then
    /usr/sbin/ipsec &
    sleep 10
    /usr/sbin/ipsec status
    CNAME=$(cat /etc/ipsec.conf | grep conn | tail -n1 | cut -d\  -f2)
    (sleep 7 && echo "c $CNAME" > /var/run/xl2tpd/l2tp-control) &
    exec /usr/sbin/xl2tpd -D
else
    (sleep 10 && /usr/sbin/ipsec status) &
    exec /usr/sbin/ipsec
fi
