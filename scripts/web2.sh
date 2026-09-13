#!/bin/bash
set -e
echo "=== Web2 Server Provisioning Start (CentOS Stream 9) ==="

# CHANGED: apt-get -> dnf. Same package mapping notes as web.sh apply here —
# see web.sh for the detailed explanation of each renamed/added package.
dnf update -y
dnf install -y python3.12 python3.12-devel
python3.12 -m ensurepip --upgrade
python3.12 -m pip install --upgrade pip
# Baaki packages
dnf install -y nginx git gcc mysql
dnf module enable mysql:8.4 -y     
dnf install -y mysql-devel pkgconfig \
    policycoreutils-python-utils \
    firewalld cronie curl
dnf install -y epel-release
dnf install -y msmtp


systemctl enable --now firewalld
systemctl enable --now crond

# Nginx default server conflict fix — CentOS Stream 9 compatible
sed -i '/listen       80/s/^/#/' /etc/nginx/nginx.conf
sed -i '/listen       \[::\]:80/s/^/#/' /etc/nginx/nginx.conf

cd /home/vagrant
if [ ! -d "proshop" ]; then
    git clone https://github.com/Dheeraj-chelani/proshop.git proshop
fi

chown -R vagrant:vagrant /home/vagrant/proshop
cd proshop

# Python 3.12 se venv banao
if [ ! -d "/home/vagrant/proshop/.venv" ]; then
    sudo -u vagrant python3.12 -m venv .venv
else
    echo ".venv already exists — skipping"
fi
sudo -u vagrant /home/vagrant/proshop/.venv/bin/pip install --upgrade pip
sudo -u vagrant /home/vagrant/proshop/.venv/bin/pip install -r requirements.txt
sudo -u vagrant /home/vagrant/proshop/.venv/bin/pip install gunicorn


# .env content unchanged — web2's IP differs from web1, same as original.
cat > /home/vagrant/proshop/.env << EOF
SECRET_KEY=${SECRET_KEY}
DEBUG=False
DB_NAME=proshop_db
DB_USER=${DB_USER}
DB_PASSWORD=${DB_PASSWORD}
DB_HOST=192.168.56.12
DB_PORT=3306
ALLOWED_HOSTS=localhost,127.0.0.1,192.168.56.11,192.168.56.10
CSRF_TRUSTED_ORIGINS=http://localhost:8001,http://localhost:8080,http://localhost:8002,http://192.168.56.10,http://192.168.56.11,http://192.168.56.13
EOF

chown vagrant:vagrant /home/vagrant/proshop/.env

DB_USER=$(grep DB_USER /home/vagrant/proshop/.env | cut -d'=' -f2)
DB_PASSWORD=$(grep DB_PASSWORD /home/vagrant/proshop/.env | cut -d'=' -f2)
DB_HOST=$(grep DB_HOST /home/vagrant/proshop/.env | cut -d'=' -f2)
DB_NAME=$(grep DB_NAME /home/vagrant/proshop/.env | cut -d'=' -f2)

echo "DB ka wait kar rahe hain..."
for i in {1..30}; do
    if mysql -u "$DB_USER" -p"$DB_PASSWORD" -h "$DB_HOST" -e "use $DB_NAME;" 2>/dev/null; then
        echo "DB ready hai!"
        break
    fi
    echo "Waiting... ($i/30)"
    sleep 2
done

# Django setup
# sudo -u vagrant /home/vagrant/proshop/.venv/bin/python manage.py migrate
sudo -u vagrant /home/vagrant/proshop/.venv/bin/python manage.py collectstatic --noinput


# Backup import
# LATEST_GZ=$(ls -t /vagrant/backups/*.sql.gz 2>/dev/null | head -1)
# LATEST_SQL=$(ls -t /vagrant/backups/*.sql 2>/dev/null | head -1)

# if [ -n "$LATEST_GZ" ]; then
#     echo "GZ Backup mil gayi: $LATEST_GZ"
#     gunzip -c "$LATEST_GZ" | mysql -u "$DB_USER" -p"$DB_PASSWORD" \
#         -h "$DB_HOST" "$DB_NAME"
#     echo "Data import complete"
# elif [ -n "$LATEST_SQL" ]; then
#     echo "SQL Backup mil gayi: $LATEST_SQL"
#     mysql -u "$DB_USER" -p"$DB_PASSWORD" -h "$DB_HOST" \
#         "$DB_NAME" < "$LATEST_SQL"
#     echo "Data import complete"
# else
#     echo "Koi backup nahi — fresh database"
# fi

echo "
from django.contrib.auth.models import User
if not User.objects.filter(is_superuser=True).exists():
    User.objects.create_superuser('admin', 'admin@proshop.com', 'admin@123')
    print('Superuser created')
else:
    print('Superuser already exists')
" | sudo -u vagrant /home/vagrant/proshop/.venv/bin/python manage.py shell

# CHANGED: Group=www-data -> Group=nginx (see web.sh for reasoning).
cat > /etc/systemd/system/gunicorn.service << 'EOF'
[Unit]
Description=Gunicorn daemon for Proshop
After=network.target

[Service]
User=vagrant
Group=nginx
WorkingDirectory=/home/vagrant/proshop
ExecStart=/home/vagrant/proshop/.venv/bin/gunicorn \
            --access-logfile - \
            --workers 3 \
            --bind unix:/home/vagrant/proshop/gunicorn.sock \
            proshop.wsgi:application
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

# CHANGED: conf.d instead of sites-available/sites-enabled (see web.sh).
cat > /etc/nginx/conf.d/proshop.conf << 'EOF'
server {
    listen 80 ;
    server_name _;

    location = /favicon.ico { access_log off; log_not_found off; }

    location /static/ {
        alias /home/vagrant/proshop/staticfiles/;
    }

    location /media/ {
        root /home/vagrant/proshop;
    }

    location / {
        include /etc/nginx/proxy_params;
        proxy_pass http://unix:/home/vagrant/proshop/gunicorn.sock;
    }
}
EOF

# proxy_params file banao — CentOS mein default nahi hota
cat > /etc/nginx/proxy_params << 'EOF'
proxy_set_header Host $http_host;
proxy_set_header X-Real-IP $remote_addr;
proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
proxy_set_header X-Forwarded-Proto $scheme;
EOF

nginx -t

# CHANGED: www-data -> nginx
chown -R vagrant:nginx /home/vagrant/proshop
chmod -R 775 /home/vagrant/proshop
usermod -aG vagrant nginx


# Email alerting setup — msmtp + Gmail SMTP

cat > /etc/msmtprc << EOF
defaults
auth           on
tls            on
tls_trust_file /etc/pki/tls/certs/ca-bundle.crt
logfile        /var/log/msmtp.log

account        gmail
host           smtp.gmail.com
port           587
from           ${GMAIL}
user           ${GMAIL}
password       ${GMAIL_PASSWORD}

account default : gmail
EOF
chmod 600 /etc/msmtprc


# SELinux settings
setsebool -P httpd_can_network_connect 1
setsebool -P httpd_read_user_content 1
setsebool -P httpd_enable_homedirs 1

# SELinux context set karo
semanage fcontext -a -t httpd_sys_content_t \
    "/home/vagrant/proshop(/.*)?"
restorecon -Rv /home/vagrant/proshop

# Firewall
firewall-cmd --permanent --add-port=80/tcp
firewall-cmd --reload

# Timezone + Cron
timedatectl set-timezone Asia/Kolkata
(crontab -l 2>/dev/null || true; echo "*/5 * * * * /bin/bash /vagrant/scripts/monitor.sh") | crontab -

systemctl daemon-reload
systemctl enable gunicorn
systemctl start gunicorn

# ADDED: relabel again after the socket file is actually created at runtime.
sleep 3
semanage fcontext -a -t httpd_var_run_t \
    "/home/vagrant/proshop/gunicorn.sock"
restorecon -Rv /home/vagrant/proshop

systemctl restart nginx
systemctl enable nginx

echo "=== Web2 Server Provisioning Complete (CentOS Stream 9) ==="
echo "Site: http://localhost:8002"
