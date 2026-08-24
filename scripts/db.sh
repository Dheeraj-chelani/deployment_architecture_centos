#!/bin/bash
set -e
echo "=== Database Server Provisioning Start (CentOS Stream 9) ==="

dnf update -y
dnf install -y mysql-server

if ! command -v firewall-cmd &>/dev/null; then
    dnf install -y firewalld
fi
systemctl enable --now firewalld

systemctl start mysqld
systemctl enable mysqld

# MySQL start hone ka wait karo
echo "Waiting for MySQL to start..."
for i in {1..30}; do
    if mysqladmin ping --silent 2>/dev/null; then
        echo "MySQL ready!"
        break
    fi
    sleep 2
done

# CentOS MySQL 8 mein fresh install pe root
# empty password se socket ke through login hota hai
# Temporary password check karo pehle
TEMP_PASS=""
if [ -f /var/log/mysqld.log ]; then
    TEMP_PASS=$(grep 'temporary password' /var/log/mysqld.log \
        | awk '{print $NF}' | tail -1)
fi

if [ -n "$TEMP_PASS" ]; then
    echo "Temporary password mili — reset kar rahe hain"
    mysql -u root -p"$TEMP_PASS" \
        --connect-expired-password \
        -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '';"
fi

# Ab empty password se login karo
# validate_password plugin disable karo
mysql -u root -e "UNINSTALL COMPONENT 'file://component_validate_password';" \
    2>/dev/null || true

# Config file update — bind-address
CONF_FILE="/etc/my.cnf.d/mysql-server.cnf"
if grep -q "^bind-address" "$CONF_FILE" 2>/dev/null; then
    sed -i "s/^bind-address.*/bind-address = 0.0.0.0/" "$CONF_FILE"
else
    echo "bind-address = 0.0.0.0" >> "$CONF_FILE"
fi

DB_NAME="proshop_db"
DB_USER="${DB_USER}"
DB_PASSWORD="${DB_PASSWORD}"

# Database aur user banao
mysql -u root -e "CREATE DATABASE IF NOT EXISTS ${DB_NAME} \
    CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
mysql -u root -e "CREATE USER IF NOT EXISTS \
    '${DB_USER}'@'%' IDENTIFIED BY '${DB_PASSWORD}';"
mysql -u root -e "GRANT ALL PRIVILEGES ON ${DB_NAME}.* \
    TO '${DB_USER}'@'%';"
mysql -u root -e "FLUSH PRIVILEGES;"

# Firewall
firewall-cmd --permanent --add-port=3306/tcp
firewall-cmd --reload

# Restart with new bind-address
systemctl restart mysqld

echo "=== Database Server Provisioning Complete (CentOS Stream 9) ==="






























# #!/bin/bash
# set -e
# echo "=== Database Server Provisioning Start (CentOS Stream 9) ==="

# # CHANGED: apt-get -> dnf (CentOS/RHEL package manager)
# dnf update -y

# # CHANGED: mysql-server package name is the same in RHEL9's AppStream repo,
# # so no rename needed here — dnf just resolves it from a different repo.
# dnf install -y mysql-server

# # ADDED: firewalld ships enabled+running by default on CentOS/RHEL (unlike
# # Ubuntu, which had no active firewall in the original script). We defensively
# # install it too in case a minimal base box stripped it out.
# if ! command -v firewall-cmd &>/dev/null; then
#     dnf install -y firewalld
# fi
# systemctl enable --now firewalld

# # CHANGED: the systemd service is named "mysqld" on RHEL/CentOS,
# # not "mysql" like on Ubuntu/Debian.
# systemctl start mysqld
# systemctl enable mysqld

# sleep 5  # wait a few seconds for mysqld to start up before we try to connect
# TEMP_PASSWORD=$(grep 'temporary password' /var/log/mysqld.log | awk '{print $NF}')
# mysql -u root -p"$TEMP_PASSWORD" --connect-expired-password -e "ALTER USER 'root'@'localhost' IDENTIFIED BY 'RootPass@123';"

# mysql -u root -p'RootPass@123' -e "SET GLOBAL validate_password.policy=LOW;"
# mysql -u root -p'RootPass@123' -e "SET GLOBAL validate_password.length=6;"
# # CHANGED: config file path differs between distros.
# #   Ubuntu:     /etc/mysql/mysql.conf.d/mysqld.cnf
# #   CentOS 9:   /etc/my.cnf.d/mysql-server.cnf
# CONF_FILE="/etc/my.cnf.d/mysql-server.cnf"

# # CHANGED: made idempotent + safer. RHEL's default config file frequently has
# # NO bind-address line at all (Ubuntu's always ships one), so blindly running
# # `sed -i 's/bind-address.*/.../''` like the Ubuntu version would silently do
# # nothing. We check first, and append the line if it's missing.
# if grep -q "^bind-address" "$CONF_FILE" 2>/dev/null; then
#     sed -i "s/^bind-address.*/bind-address = 0.0.0.0/" "$CONF_FILE"
# else
#     echo "bind-address = 0.0.0.0" >> "$CONF_FILE"
# fi

# DB_NAME="proshop_db"
# DB_USER="harry"
# DB_PASSWORD="password"

# # NOTE: RHEL9's mysql-server AppStream module authenticates local root via a
# # socket-based plugin by default (same idea as Ubuntu's setup), so `mysql -e`
# # as root without a password should still work here. If your particular base
# # box behaves differently and prompts for a password, run
# # `mysql_secure_installation` once manually before this script, or check
# # /var/log/mysqld.log for a generated temporary root password.
# mysql -u root -pRootPass@123 -e \
#     "CREATE DATABASE IF NOT EXISTS ${DB_NAME} CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
# mysql -u root -pRootPass@123 -e \
#     "CREATE USER IF NOT EXISTS '${DB_USER}'@'%' IDENTIFIED BY '${DB_PASSWORD}';"
# mysql -u root -pRootPass@123 -e \
#     "GRANT ALL PRIVILEGES ON ${DB_NAME}.* TO '${DB_USER}'@'%';"
# mysql -u root -pRootPass@123 -e "FLUSH PRIVILEGES;"

# # ADDED: open MySQL's port in firewalld — Ubuntu's script never needed this
# # because there was no firewall blocking anything by default.
# firewall-cmd --permanent --add-port=3306/tcp
# firewall-cmd --reload

# # CHANGED: restart mysqld, not mysql
# systemctl restart mysqld

# echo "=== Database Server Provisioning Complete (CentOS Stream 9) ==="
