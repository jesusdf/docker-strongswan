#!/bin/sh

C=US
O=StrongSwan
CA_CN=strongswan.org
SERVER_CN=moon.strongswan.org
SERVER_SAN=moon.strongswan.org
CLIENT_CN="carol@strongswan.org"

CONFIG_DIR=$PWD/config/swanctl
PKI="docker run -it --rm=true -v $CONFIG_DIR:/etc/swanctl jesusdf/docker-strongswan pki"

mkdir -p $CONFIG_DIR/x509ca \
         $CONFIG_DIR/x509 \
         $CONFIG_DIR/private

$PKI --gen --outform pem > $CONFIG_DIR/private/caKey.pem
$PKI --self --in /etc/swanctl/private/caKey.pem --dn "C=$C, O=$O, CN=$CA_CN" --ca --outform pem > $CONFIG_DIR/x509ca/caCert.pem

$PKI --gen --outform pem > $CONFIG_DIR/private/serverKey.pem
$PKI --issue --in /etc/swanctl/private/serverKey.pem --type priv --cacert /etc/swanctl/x509ca/caCert.pem --cakey /etc/swanctl/private/caKey.pem --dn "C=$C, O=$O, CN=$SERVER_CN" --san="$SERVER_SAN" --flag serverAuth --flag ikeIntermediate --outform pem > $CONFIG_DIR/x509/serverCert.pem

$PKI --gen --outform pem > $CONFIG_DIR/private/clientKey.pem
$PKI --issue --in /etc/swanctl/private/clientKey.pem --type priv --cacert /etc/swanctl/x509ca/caCert.pem --cakey /etc/swanctl/private/caKey.pem --dn "C=$C, O=$O, CN=$CLIENT_CN" --san="$CLIENT_CN" --outform pem > $CONFIG_DIR/x509/clientCert.pem
openssl pkcs12 -export -inkey $CONFIG_DIR/private/clientKey.pem -in $CONFIG_DIR/x509/clientCert.pem -name "$CLIENT_CN" -certfile $CONFIG_DIR/x509ca/caCert.pem -caname "$CA_CN" -out $CONFIG_DIR/clientCert.p12
