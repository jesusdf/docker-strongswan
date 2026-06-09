#!/bin/bash
set -euo pipefail

SERVER="${1:?Usage: $0 <host-or-ip> [port]}"
PORT="${2:-443}"
OUTPUT_DIR="./config/swanctl/x509ca"
OUTPUT_FILE="$OUTPUT_DIR/caCert.pem"

command -v openssl >/dev/null 2>&1 || { echo "Error: openssl is required"; exit 1; }

mkdir -p "$OUTPUT_DIR"

echo "Connecting to $SERVER:$PORT ..."
CHAIN=$(openssl s_client \
    -connect "$SERVER:$PORT" \
    -servername "$SERVER" \
    -showcerts \
    </dev/null 2>/dev/null) || {
    echo "Error: could not connect to $SERVER:$PORT"
    exit 1
}

# Parse PEM blocks into an array
certs=()
current=""
while IFS= read -r line; do
    if [[ "$line" == "-----BEGIN CERTIFICATE-----" ]]; then
        current="$line"$'\n'
    elif [[ -n "$current" ]]; then
        current+="$line"$'\n'
        if [[ "$line" == "-----END CERTIFICATE-----" ]]; then
            certs+=("$current")
            current=""
        fi
    fi
done <<< "$CHAIN"

[[ ${#certs[@]} -gt 0 ]] || { echo "Error: no certificates found in server response"; exit 1; }

echo "Found ${#certs[@]} certificate(s) in chain."

# Look for a self-signed CA cert (subject == issuer and CA:TRUE).
# Fall back to the last cert in the chain if none qualifies.
root_ca=""
for cert in "${certs[@]}"; do
    subject=$(echo "$cert" | openssl x509 -noout -subject 2>/dev/null | sed 's/^subject=\s*//')
    issuer=$(echo  "$cert" | openssl x509 -noout -issuer  2>/dev/null | sed 's/^issuer=\s*//')
    is_ca=$(echo   "$cert" | openssl x509 -noout -text    2>/dev/null | grep -c "CA:TRUE" || true)
    if [[ "$subject" == "$issuer" && "$is_ca" -gt 0 ]]; then
        root_ca="$cert"
        break
    fi
done

if [[ -z "$root_ca" ]]; then
    echo "Warning: no self-signed CA certificate found, using last certificate in chain"
    root_ca="${certs[-1]}"
fi

echo
echo "CA certificate:"
echo "$root_ca" | openssl x509 -noout -subject -issuer -dates 2>/dev/null
echo

if [[ -f "$OUTPUT_FILE" ]]; then
    echo "Warning: $OUTPUT_FILE already exists, overwriting"
fi

echo "$root_ca" > "$OUTPUT_FILE"
echo "Saved to $OUTPUT_FILE"
