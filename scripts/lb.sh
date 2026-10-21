#!/bin/bash
set -e
echo "=== Load Balancer Provisioning Start (CentOS Stream 9) ==="

# CHANGED: apt-get -> dnf
dnf update -y


dnf install -y nginx curl policycoreutils-python-utils firewalld cronie
dnf install -y epel-release
dnf install -y msmtp

systemctl enable --now firewalld
systemctl enable --now crond


cat > /etc/nginx/conf.d/loadbalancer.conf << 'EOF'
upstream django_servers {
    server 192.168.56.11:80;
    server 192.168.56.13:80;
}

server {
    listen 80 ;
    server_name _;

    location / {
        proxy_pass http://django_servers;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
EOF

setsebool -P httpd_can_network_connect on

# ADDED: firewalld — open port 80 (Ubuntu script needed no firewall rule
# since nothing was blocking traffic there by default).
firewall-cmd --permanent --add-port=80/tcp
firewall-cmd --reload

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

# Timezone command is identical on both distros (systemd timedatectl).
timedatectl set-timezone Asia/Kolkata

# Cron syntax itself is unchanged from the Ubuntu version — only difference
# is we had to explicitly install+enable cronie/crond above first.
(crontab -l 2>/dev/null || true; echo "*/5 * * * * /bin/bash /vagrant/scripts/lb_monitor.sh") | crontab -

nginx -t
systemctl enable nginx
systemctl restart nginx

echo "=== Load Balancer Provisioning Complete (CentOS Stream 9) ==="
echo "LB available at: http://localhost:8080"
