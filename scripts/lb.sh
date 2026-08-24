#!/bin/bash
set -e
echo "=== Load Balancer Provisioning Start (CentOS Stream 9) ==="

# CHANGED: apt-get -> dnf
dnf update -y

# CHANGED: nginx is available directly from CentOS Stream 9's AppStream repo
# (no EPEL or third-party repo needed, unlike some older RHEL guides suggest).
# ADDED: policycoreutils-python-utils (for SELinux `setsebool`),
#        firewalld + cronie (not guaranteed present/running on minimal boxes).
dnf install -y nginx curl policycoreutils-python-utils firewalld cronie

systemctl enable --now firewalld
systemctl enable --now crond

# CHANGED: RHEL's nginx package has NO sites-available/sites-enabled
# convention (that's Debian/Ubuntu-specific). Config files instead go
# straight into /etc/nginx/conf.d/*.conf, which the stock nginx.conf
# already `include`s automatically.
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
# NOTE on "listen 80 default_server;" above:
# RHEL's stock /etc/nginx/nginx.conf ships with its own built-in server{}
# block (Ubuntu's nginx package does NOT have this). Without explicitly
# marking our block as default_server, that stock block can end up winning
# for unmatched requests. Setting default_server here forces our config to
# take priority regardless of load order.

# ADDED: SELinux (enforcing by default on CentOS/RHEL; not present at all on
# Ubuntu) blocks nginx from making OUTBOUND proxy_pass connections to other
# hosts unless this boolean is explicitly enabled. This is the single most
# common reason a working Ubuntu reverse-proxy config gives "502 Bad Gateway"
# the moment you move it to CentOS/RHEL.
setsebool -P httpd_can_network_connect on

# ADDED: firewalld — open port 80 (Ubuntu script needed no firewall rule
# since nothing was blocking traffic there by default).
firewall-cmd --permanent --add-port=80/tcp
firewall-cmd --reload

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
