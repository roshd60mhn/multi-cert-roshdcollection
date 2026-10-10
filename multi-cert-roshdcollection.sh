#!/usr/bin/env bash

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info() {
    echo -e "${GREEN}[+]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[!]${NC} $1"
}

error() {
    echo -e "${RED}[x]${NC} $1"
    exit 1
}

if [[ "${EUID}" -ne 0 ]]; then
    error "This script must be run as root."
fi

if [[ ! -f /etc/os-release ]]; then
    error "Operating system could not be detected."
fi

source /etc/os-release

if [[ "${ID}" != "ubuntu" ]]; then
    warn "This script is designed for Ubuntu."
fi

echo
echo "╔════════════════════════════════════════════╗"
echo "║        Multi-Domain SSL Installer          ║"
echo "╠════════════════════════════════════════════╣"
echo "║                                            ║"
echo "║  Developer : @roshdcollection              ║"
echo "║                                            ║"
echo "║  Let's Encrypt + Certbot                   ║"
echo "║  Multi-Domain SAN Certificate              ║"
echo "║                                            ║"
echo "╚════════════════════════════════════════════╝"
echo

info "Checking required packages..."

apt-get update
apt-get install -y certbot

info "Certbot is ready."

echo
info "Checking port 80..."

if ss -ltn | grep -q ':80 '; then
    warn "Port 80 is already in use."

    echo
    echo "Services using port 80:"
    ss -ltnp | grep ':80 ' || true

    echo
    echo "1) Stop the service using port 80"
    echo "2) Cancel"
    echo

    read -r -p "Choose an option [1-2]: " PORT_OPTION </dev/tty

    case "$PORT_OPTION" in
        1)
            info "Detecting service using port 80..."

            PIDS=$(ss -ltnp 2>/dev/null \
                | grep ':80 ' \
                | grep -o 'pid=[0-9]*' \
                | cut -d= -f2 \
                | sort -u)

            if [[ -z "$PIDS" ]]; then
                error "Could not determine the process using port 80."
            fi

            echo
            info "Processes using port 80:"

            for PID in $PIDS; do
                ps -p "$PID" -o pid=,comm=,args= || true
            done

            echo
            read -r -p "Stop these processes and free port 80? [y/N]: " CONFIRM </dev/tty

            if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
                info "Cancelled."
                exit 0
            fi

            for PID in $PIDS; do
                info "Stopping PID $PID..."
                kill "$PID" 2>/dev/null || true
            done

            sleep 2

            if ss -ltn | grep -q ':80 '; then
                warn "Port 80 is still in use."
                error "Could not free port 80."
            fi

            info "Port 80 is now available."
            ;;

        2)
            info "Cancelled."
            exit 0
            ;;

        *)
            error "Invalid option."
            ;;
    esac
else
    info "Port 80 is available."
fi

echo
read -r -p "Certificate name: " CERT_NAME </dev/tty

if [[ -z "$CERT_NAME" ]]; then
    error "Certificate name cannot be empty."
fi

if [[ ! "$CERT_NAME" =~ ^[a-zA-Z0-9._-]+$ ]]; then
    error "Invalid certificate name."
fi

echo
read -r -p "Email for Let's Encrypt: " EMAIL </dev/tty

if [[ ! "$EMAIL" =~ ^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$ ]]; then
    error "Invalid email address."
fi

echo
info "Enter all domains that should be included in ONE certificate."
info "Enter one domain per line."
info "Press Enter on an empty line when finished."
echo

DOMAINS=()

while true; do
    read -r -p "Domain: " DOMAIN </dev/tty

    if [[ -z "$DOMAIN" ]]; then
        break
    fi

    DOMAIN="${DOMAIN,,}"

    if [[ "$DOMAIN" =~ ^[a-z0-9]([a-z0-9.-]*[a-z0-9])?$ ]]; then
        if [[ ! " ${DOMAINS[*]} " =~ " ${DOMAIN} " ]]; then
            DOMAINS+=("$DOMAIN")
            info "Added: $DOMAIN"
        else
            warn "Domain already added: $DOMAIN"
        fi
    else
        warn "Invalid domain: $DOMAIN"
    fi
done

if [[ "${#DOMAINS[@]}" -eq 0 ]]; then
    error "No domains were entered."
fi

echo
info "One certificate will be created for these domains:"
echo

for DOMAIN in "${DOMAINS[@]}"; do
    echo "  ✓ $DOMAIN"
done

echo

read -r -p "Continue? [Y/n]: " CONFIRM </dev/tty

if [[ "$CONFIRM" =~ ^[Nn]$ ]]; then
    info "Cancelled."
    exit 0
fi

echo
info "Requesting Multi-Domain SAN certificate..."

CERTBOT_ARGS=(
    certonly
    --standalone
    --non-interactive
    --agree-tos
    --email "$EMAIL"
    --keep-until-expiring
    --cert-name "$CERT_NAME"
)

for DOMAIN in "${DOMAINS[@]}"; do
    CERTBOT_ARGS+=("-d" "$DOMAIN")
done

certbot "${CERTBOT_ARGS[@]}"

echo
info "Certificate created successfully."

echo
info "Certificate information:"
certbot certificates

echo
info "Certificate paths:"
echo
echo "Certificate:"
echo "/etc/letsencrypt/live/${CERT_NAME}/fullchain.pem"
echo
echo "Private key:"
echo "/etc/letsencrypt/live/${CERT_NAME}/privkey.pem"

echo
info "Testing automatic renewal..."

if certbot renew --dry-run; then
    info "Automatic renewal test passed."
else
    warn "Automatic renewal test failed."
    warn "Check the output above before using this certificate in production."
fi

echo
echo "╔════════════════════════════════════════════╗"
echo "║          SSL Setup Completed               ║"
echo "╠════════════════════════════════════════════╣"
echo "║                                            ║"
echo "║  Certificate:                              ║"
echo "║  /etc/letsencrypt/live/${CERT_NAME}/      ║"
echo "║                                            ║"
echo "╚════════════════════════════════════════════╝"
echo

info "Multi-Domain SSL installation completed."
