# StrongSwan VPN + Alpine Linux

Forked from https://github.com/Stanback/alpine-strongswan-vpn to meet custom needs.

This repository contains a Dockerfile for generating
an image with [StrongSwan](https://www.strongswan.org/) and
[Alpine Linux](https://alpinelinux.org/).

This image can be used on the server or client in a variety
of configurations. It uses the modern `swanctl` / VICI interface
(replacing the legacy `ipsec` starter).

The reference configuration in this repository and following
guidelines are intended to provide an attempt at a
best-practice example for setting up a universal VPN server
that can handle modern IKEv2 roadwarrior clients (with IPv6
support in mind).

## Server Setup

### Gather necessary files

Clone this repository and use the files in `config/` as a starting point:

* `generate_certs.sh`
* `config/`
    * `config/swanctl/swanctl.conf`
    * `config/strongswan.conf`
    * `config/swanctl/updown/firewall.updown`

### Edit configuration, setup certificates

Edit `config/swanctl/swanctl.conf` to your liking. Key settings to review:

* `secrets { eap-carol { secret = ... } }` — change EAP credentials
* `connections { roadwarrior { local { id = ... } } }` — set your server's identity
* `pools { vpn-pool { addrs = ... } }` — adjust the IP pool assigned to clients
* `config/swanctl/updown/firewall.updown` — review NAT/masquerade rules

If running behind a router, forward ports **500/udp** and **4500/udp**. If you
have a local firewall, also accept protocol 50 (ESP) and protocol 51 (AH).

Also a caveat for docker hosts receiving their IP and gateway from router
advertisements: with IPv6 packet forwarding enabled, advertisements are
disabled unless you set `accept_ra=2` for your interface via sysctl or
in `/etc/network/interfaces`.

Generate your certificate signing authority, server certificate, and client
certificate by editing and running `generate_certs.sh`. Certificates are
written into `config/swanctl/`:

| Path | Description |
|---|---|
| `config/swanctl/x509ca/caCert.pem` | CA certificate |
| `config/swanctl/x509/serverCert.pem` | Server certificate |
| `config/swanctl/x509/clientCert.pem` | Client certificate |
| `config/swanctl/private/serverKey.pem` | Server private key |
| `config/swanctl/private/clientKey.pem` | Client private key |
| `config/swanctl/clientCert.p12` | Client certificate bundle (for import) |

### Start Docker container

Running this Docker container requires elevated privileges including
`--cap-add=NET_ADMIN`. It will have permission to modify your Docker
host's networking and iptables configuration.

The recommended way is with Docker Compose:

    docker compose up -d

Or manually, ensuring the `config/` folder is in your current directory:

    docker run -d \
      --cap-add=NET_ADMIN \
      --net=host \
      -v $PWD/config/strongswan.conf:/etc/strongswan.conf \
      -v $PWD/config/swanctl:/etc/swanctl \
      --name=strongswan \
      jesusdf/docker-strongswan

You may need to enable packet forwarding and NDP proxying on your
Docker host via sysctl or `/etc/sysctl.conf`:

```
sudo sysctl net.ipv4.ip_forward=1
sudo sysctl net.ipv6.conf.all.forwarding=1
sudo sysctl net.ipv6.conf.all.proxy_ndp=1
sudo iptables -A FORWARD -j ACCEPT
```

### Check status

    docker logs -f --tail 100 strongswan
    docker exec -it strongswan swanctl --list-sas
    docker exec -it strongswan swanctl --list-conns
    docker exec -it strongswan swanctl --list-pools

## Running as a VPN Client

The container can connect to a remote IPsec/IKEv2 server without any code
changes. The mechanism is straightforward: on startup, `charon` loads the
configuration from `/etc/swanctl` via VICI. If any child SA has
`start_action = start`, charon initiates that connection automatically.

### Directory layout

Mount a local folder to `/etc/swanctl` that contains at minimum:

```
config/swanctl/
├── swanctl.conf          # connection config + credentials
└── x509ca/
    └── caCert.pem        # CA certificate to verify the remote server
```

**Obtaining the CA certificate**

If the remote server also exposes HTTPS, the included `get-remote-ca.sh`
script can fetch the root CA automatically:

```bash
./get-remote-ca.sh vpn.example.com
# optionally specify a port (default: 443)
./get-remote-ca.sh vpn.example.com 8443
```

The certificate is saved to `config/swanctl/x509ca/caCert.pem`. Verify the
output before use — confirm that the subject matches the expected CA and that
the validity dates are correct.

If the server does not have HTTPS, request the CA certificate from its
administrator or export it directly from the server's
`config/swanctl/x509ca/` directory.

If the remote server requires certificate authentication add:

```
config/swanctl/
├── x509/
│   └── clientCert.pem
└── private/
    └── clientKey.pem
```

### swanctl.conf example (EAP-MSCHAPv2)

```
connections {
    myvpn {
        version = 2
        remote_addrs = vpn.example.com

        # Request a virtual IP from the server
        vips = 0.0.0.0

        local {
            auth = eap-mschapv2
            id = myusername
        }
        remote {
            auth = pubkey
            id = vpn.example.com
        }
        children {
            myvpn {
                # Route all traffic through the tunnel
                remote_ts = 0.0.0.0/0, ::/0

                # Auto-connect on startup and reconnect on drop
                start_action = start
                close_action = start
                dpd_action = restart
            }
        }
    }
}

secrets {
    eap-myuser {
        id = myusername
        secret = mypassword
    }
}
```

For certificate-based authentication replace the `local` block and `secrets`
with:

```
        local {
            auth = pubkey
            certs = clientCert.pem
        }
```

### docker-compose.yml

The intended use is as a network stack for another container. Set
`network_mode: service:strongswan` on the dependent container so it shares
the strongswan network namespace — all its traffic is then routed through
the VPN tunnel automatically.

```yaml
services:
  strongswan:
    image: jesusdf/docker-strongswan:latest
    container_name: docker-strongswan
    cap_add:
      - NET_ADMIN
    devices:
      - /dev/net/tun:/dev/net/tun
    environment:
      - TZ=Europe/Madrid
    volumes:
      - ./config/strongswan.conf:/etc/strongswan.conf
      - ./config/swanctl:/etc/swanctl
    restart: unless-stopped

  myapp:
    image: myapp:latest
    network_mode: service:strongswan
    depends_on:
      - strongswan
```

> `NET_ADMIN` is required for kernel IPsec (xfrm) and route management.
> `/dev/net/tun` is required for IKEv1 and L2TP connections.

### Managing the connection

```bash
# Check current tunnel state
docker exec -it strongswan swanctl --list-sas

# Initiate manually (if start_action = none)
docker exec -it strongswan swanctl --initiate --child myvpn

# Bring the tunnel down
docker exec -it strongswan swanctl --terminate --ike myvpn

# Reload config after editing swanctl.conf
docker exec -it strongswan swanctl --load-all
```

## Client Setup

### macOS

Crypto: IKEv2 AES256-SHA256-MODP2048

Import and trust the CA certificate from `config/swanctl/x509ca/caCert.pem`
and the client certificate from the exported `config/swanctl/clientCert.p12`.
For iOS, you can email yourself the `.pem` and `.p12` files and import them
as a new profile.

* For EAP password authentication: select **Username**
* For EAP certificate authentication: select **Certificate**
* For pubkey certificate authentication: select **None** and select the cert

### Windows 10/11

Crypto: IKEv2 AES256-SHA256-MODP1024

Import the certificates into your trusted root CA store (Machine) from the
exported `config/swanctl/clientCert.p12`.

After creating the VPN connection, go to the properties for the network
connection, click on the Networking tab, and go to the IPv4 connection
properties. Click Advanced and check "Use default gateway on remote network"
to enable tunneling.

To enable IPv6 gateway, run as administrator:

    netsh int ipv6 show interfaces
    netsh interface ipv6 add route ::/0 interface=INTERFACE_NUMBER

In Windows, MODP2048 Diffie-Hellman is disabled by default. Enable it by
setting the following registry `REG_DWORD` to `1`:

    HKEY_LOCAL_MACHINE\System\CurrentControlSet\Services\Rasman\Parameters\NegotiateDH2048_AES256

### iOS

Crypto: IKEv2 AES256-SHA256-MODP2048

Go to Settings → General → VPN → Add VPN Configuration → Type: IKEv2.
Enter a description, server address, remote ID, and local ID (typically
your username). For authentication, select **Username** for EAP+MSCHAPv2,
**Certificate** for EAP+TLS, or **None** for pubkey/PSK.

### Android

Crypto: IKEv2 CHACHA20POLY1305-PRFSHA256-ECP256

Use the [strongSwan VPN Client](https://play.google.com/store/apps/details?id=org.strongswan.android).
Native Android VPN is limited to IKEv1 which is not supported by this configuration.

### Linux

Crypto: IKEv2 CHACHA20POLY1305-PRFSHA256-NEWHOPE128

In addition to serving VPN connections, StrongSwan can act as a client.
You can use this Docker image on Linux to act as a client — or both client
and server simultaneously. (Run only one instance per host.)

To configure a StrongSwan client, use the same `config/swanctl/swanctl.conf`
(the `home` connection is pre-configured as a client). Start the container
the same way as for the server, then manage the connection with `swanctl`:

    docker exec -it strongswan swanctl --initiate --child home
    docker exec -it strongswan swanctl --list-sas
    docker exec -it strongswan swanctl --terminate --ike home

You can also install the `strongswan` and `strongswan-swanctl` packages from
your Linux distribution and use `config/` as a reference. A NetworkManager
plugin is also available (Ubuntu package: `network-manager-strongswan`).

## Other Info

### Cipher Suites

This configuration attempts to balance higher-grade ciphers with performance
and compatibility with the latest versions of macOS, Windows, Linux, and
mobile devices. The cipher list is intentionally kept short; modify it in
`swanctl.conf` if stronger encryption is required.

### References

* [swanctl Reference](https://docs.strongswan.org/docs/5.9/swanctl/swanctlConf.html)
* [swanctl Command](https://docs.strongswan.org/docs/5.9/swanctl/swanctl.html)
* [IKEv2 Cipher Suites](https://wiki.strongswan.org/projects/strongswan/wiki/IKEv2CipherSuites)
* [StrongSwan IKEv2 Tests](https://www.strongswan.org/testresults.html)
* [StrongSwan on Windows](https://wiki.strongswan.org/projects/strongswan/wiki/Windows7)
* [FARP for IPv6](https://wiki.strongswan.org/issues/1008)
