#!/bin/bash
# bash -c "$(wget -qLO - https://raw.githubusercontent.com/egmsystems/ProxmoxVE/refs/heads/main/lxc/nginxProxyManager.sh)"
echo "Create inner"

silent() { "$@" >/dev/null 2>&1; }

echo "apt-cacher setting"
echo $aptproxy > /etc/apt/apt.conf.d/00aptproxy
cat /etc/apt/apt.conf.d/00aptproxy
echo "apt-cacher setted"

echo "os updating"
$STD apt-get -y upgrade
$STD apt-get -y update
echo "os updated"

echo "dependences installing"
$STD apt-get -y install \
  curl \
  git \
  logrotate
echo "dependences installed"

echo "python dependencies Installing"
$STD apt-get install -y \
  python3 \
  python3-dev \
  python3-pip \
  python3-venv \
  python3-cffi \
  python3-certbot \
  python3-certbot-dns-cloudflare
$STD pip3 install certbot-dns-multi
$STD python3 -m venv /opt/certbot/
rm -rf /usr/lib/python3.*/EXTERNALLY-MANAGED
echo "python dependencies Installed"

echo "nginx Installing"
$STD apt-get -y install nginx
echo "nginx Installed"

#$STD npm install -g pnpm@8.15
echo "node.js Installing"
$STD bash <(curl -fsSL https://deb.nodesource.com/setup_16.x)
$STD apt-get install -y nodejs
node -v
echo "node.js Installed"

echo "npm installing"
#$STD git clone https://github.com/jc21/nginx-proxy-manager.git
RELEASE=$(curl -s https://api.github.com/repos/NginxProxyManager/nginx-proxy-manager/releases/latest |
  grep "tag_name" |
  awk '{print substr($2, 3, length($2)-4) }')
wget -q https://codeload.github.com/NginxProxyManager/nginx-proxy-manager/tar.gz/v${RELEASE} -O - | tar -xz
cd ./nginx-proxy-manager-${RELEASE}
echo "npm installing"

echo "env setting"
sed -i "s|\"version\": \"0.0.0\"|\"version\": \"$RELEASE\"|" backend/package.json
sed -i "s|\"version\": \"0.0.0\"|\"version\": \"$RELEASE\"|" frontend/package.json
sed -i "s|https://github.com.*source=nginx-proxy-manager|egmsystems|g" frontend/js/app/ui/footer/main.ejs
sed -i 's+^daemon+#daemon+g' docker/rootfs/etc/nginx/nginx.conf
NGINX_CONFS=$(find "$(pwd)" -type f -name "*.conf")
for NGINX_CONF in $NGINX_CONFS; do
  sed -i 's+include conf.d+include /etc/nginx/conf.d+g' "$NGINX_CONF"
done
sed -i 's/user npm/user root/g; s/^pid/#pid/g' /usr/local/openresty/nginx/conf/nginx.conf
sed -r -i 's/^([[:space:]]*)su npm npm/\1#su npm npm/g;' /etc/logrotate.d/nginx-proxy-manager
sed -i 's/include-system-site-packages = false/include-system-site-packages = true/g' /opt/certbot/pyvenv.cfg
mkdir -p /tmp/nginx/body \
  /data \
  /app/global \
  /app/frontend \
  /app/frontend/images \
  /var/www/html  \
  /var/cache/nginx/proxy_temp \
  /etc/nginx/logs \
  /etc/nginx/conf
cp -r docker/rootfs /
ln -sf /etc/nginx/nginx.conf /etc/nginx/conf/nginx.conf
rm -f /etc/nginx/conf.d/dev.conf
cp -r backend /app
cp -r global/*.* /app/global/
chmod -R 777 /var/cache/nginx
chown root /tmp/nginx
echo "env setted"

echo "npm setting"
touch /data/keys.json
chmod 660 /data/keys.json
echo "
export DB_MYSQL_HOST=$DB_MYSQL_HOST
export DB_MYSQL_USER=$DB_MYSQL_USER
export DB_MYSQL_PASSWORD="$DB_MYSQL_PASSWORD"
export DB_MYSQL_NAME=$DB_MYSQL_NAME
" > /root/.env
env
echo "npm setted"

echo "frontend installing"
cd ./frontend
$STD npm install
$STD npm upgrade
$STD npm run build
cp -r dist/* /app/frontend
cp -r app-images/* /app/frontend/images
echo "frontend installed"

echo "backend installing"
cd /app
$STD npm install --production
$STD npm upgrade
echo "backend installed"

echo "service starting"
cat <<'EOF' >/lib/systemd/system/npm.service
[Unit]
Description=Nginx Proxy Manager
After=network.target
Wants=openresty.service

[Service]
Type=simple
Environment=NODE_ENV=production
ExecStartPre=-mkdir -p /tmp/nginx/body /data/letsencrypt-acme-challenge
ExecStart=/usr/bin/node index.js --abort_on_uncaught_exception --max_old_space_size=250
WorkingDirectory=/app
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now npm
echo "service started"

echo "Cleaning up"
cd ..
#rm -rf nginx-proxy-manager-*
$STD apt-get -y autoremove
$STD apt-get -y autoclean
echo "Cleaned"

curl "http://$(hostname -I)"
echo "http://$(hostname -I)"
#exit
