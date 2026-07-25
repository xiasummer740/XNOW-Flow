#!/bin/bash
set -e

echo "=== 1. Install nginx ==="
apt update -qq
apt install -y -qq nginx

echo "=== 2. Create SSL dir ==="
mkdir -p /etc/nginx/ssl

echo "=== 3. Generate self-signed cert ==="
openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
  -keyout /etc/nginx/ssl/xnow.key \
  -out /etc/nginx/ssl/xnow.crt \
  -subj "/CN=192.129.210.52"

echo "=== 4. Write nginx config ==="
cat > /etc/nginx/sites-enabled/xnow-wss << 'NGINX_EOF'
server {
    listen 443 ssl;
    server_name 192.129.210.52;

    ssl_certificate /etc/nginx/ssl/xnow.crt;
    ssl_certificate_key /etc/nginx/ssl/xnow.key;

    location /ws/ {
        proxy_pass http://127.0.0.1:8000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_read_timeout 86400s;
        proxy_send_timeout 86400s;
    }
}
NGINX_EOF

echo "=== 5. Test nginx config ==="
nginx -t

echo "=== 6. Restart nginx ==="
systemctl restart nginx

echo "=== 7. Check nginx status ==="
systemctl is-active nginx

echo "=== 8. Allow 443 in firewall ==="
ufw allow 443/tcp 2>/dev/null || true

echo "=== 9. Test ==="
curl -sk -o /dev/null -w "HTTP %{http_code}\n" https://127.0.0.1/ws/test || true
