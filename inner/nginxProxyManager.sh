#!/bin/bash
# bash -c "$(wget -qLO - https://raw.githubusercontent.com/egmsystems/ProxmoxVE/refs/heads/main/lxc/nginxProxyManager.sh)"
echo "egmPCTcreate inner"

silent() { "$@" >/dev/null 2>&1; }

echo "Configurando apt-cacher"
echo $aptproxy > /etc/apt/apt.conf.d/00aptproxy
cat /etc/apt/apt.conf.d/00aptproxy
echo "apt-cacher Configurado"

echo "Actualizsando SO"
$STD apt-get -y upgrade
$STD apt-get -y update
echo "SO Actualizsado"

echo "Installing dependences"
$STD apt-get -y install \
  curl \
  git \
  logrotate
echo "Installed dependences"

echo "Installing Nginx"
$STD apt-get -y install nginx
echo "Downloaded Nginx"

#$STD npm install -g pnpm@8.15
echo "Installing Node.js"
$STD bash <(curl -fsSL https://deb.nodesource.com/setup_16.x)
$STD apt-get install -y nodejs
node -v
echo "Installed Node.js"

echo "Installing npm"
#$STD git clone https://github.com/jc21/nginx-proxy-manager.git
RELEASE=$(curl -s https://api.github.com/repos/NginxProxyManager/nginx-proxy-manager/releases/latest |
  grep "tag_name" |
  awk '{print substr($2, 3, length($2)-4) }')
echo "Downloading Nginx Proxy Manager v${RELEASE}"
wget -q https://codeload.github.com/NginxProxyManager/nginx-proxy-manager/tar.gz/v${RELEASE} -O - | tar -xz
cd ./nginx-proxy-manager-${RELEASE}
echo "Downloaded Nginx Proxy Manager v${RELEASE}"

echo "Setting up Enviroment"
sed -i "s|\"version\": \"0.0.0\"|\"version\": \"$RELEASE\"|" backend/package.json
sed -i "s|\"version\": \"0.0.0\"|\"version\": \"$RELEASE\"|" frontend/package.json
sed -i "s|https://github.com.*source=nginx-proxy-manager|egmsystems|g" frontend/js/app/ui/footer/main.ejs
sed -i 's+^daemon+#daemon+g' docker/rootfs/etc/nginx/nginx.conf
NGINX_CONFS=$(find "$(pwd)" -type f -name "*.conf")
for NGINX_CONF in $NGINX_CONFS; do
  sed -i 's+include conf.d+include /etc/nginx/conf.d+g' "$NGINX_CONF"
done
mkdir -p /tmp/nginx/body \
  /data \
  /app/global \
  /app/frontend \
  /app/frontend/images \
  /var/www/html  \
  /var/cache/nginx/proxy_temp \
  /etc/nginx/logs \
  /etc/nginx/conf
cp -r docker/rootfs/var/www/html/* /var/www/html/
cp -r docker/rootfs/etc/nginx/* /etc/nginx/
cp docker/rootfs/etc/letsencrypt.ini /etc/letsencrypt.ini
cp docker/rootfs/etc/logrotate.d/nginx-proxy-manager /etc/logrotate.d/nginx-proxy-manager
ln -sf /etc/nginx/nginx.conf /etc/nginx/conf/nginx.conf
rm -f /etc/nginx/conf.d/dev.conf
cp -r backend/* /app
cp -r global/* /app/global
chmod -R 777 /var/cache/nginx
chown root /tmp/nginx
echo "Installed npm"

echo "Setting npm"
touch /data/keys.json
chmod 660 /data/keys.json
echo "
export DB_MYSQL_HOST=$DB_MYSQL_HOST
export DB_MYSQL_USER=$DB_MYSQL_USER
export DB_MYSQL_PASSWORD="$DB_MYSQL_PASSWORD"
export DB_MYSQL_NAME=$DB_MYSQL_NAME
" > /root/.env
env
echo "Setted npm"

echo "Building Frontend"
cd ./frontend
$STD npm install
$STD npm upgrade
$STD npm run build
cp -r dist/* /app/frontend
cp -r app-images/* /app/frontend/images
echo "Built Frontend"

echo "Installing backend"
cd /app
$STD npm install --production
$STD npm upgrade
echo "Installed backend"

echo "Starting npm"
node index.js localhost:81
echo "Started npm"

echo "Cleaning up"
cd ..
rm -rf nginx-proxy-manager-*
$STD apt-get -y autoremove
$STD apt-get -y autoclean
echo "Cleaned"

curl "http://$(hostname -I)"
echo "http://$(hostname -I)"
#exit
