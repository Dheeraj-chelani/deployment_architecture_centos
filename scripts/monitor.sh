#!/bin/bash

# NOTE: This script needed almost NO changes for CentOS Stream 9.
# `top`, `free`, `df`, `systemctl`, and the `mysql` client command all behave
# identically on both distros (procps-ng and the MySQL client are the same
# tools either way) — only the packages providing them differ, and that's
# already handled in web.sh/web2.sh's dnf install line.


#!/bin/bash

LOG_FILE="/var/log/proshop_monitor.log"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

CPU_THRESHOLD=80
RAM_THRESHOLD=80
DISK_THRESHOLD=80

ALERT_TO="dheeraj.chelani2005@gmail.com"

CPU=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'.' -f1)
RAM=$(free | grep Mem | awk '{printf "%.0f", $3/$2 * 100}')
DISK=$(df / | tail -1 | awk '{print $5}' | cut -d'%' -f1)
NGINX=$(systemctl is-active nginx)
GUNICORN=$(systemctl is-active gunicorn 2>/dev/null || echo "N/A")

DB_USER=$(grep DB_USER /home/vagrant/proshop/.env | cut -d'=' -f2)
DB_PASSWORD=$(grep DB_PASSWORD /home/vagrant/proshop/.env | cut -d'=' -f2)
DB_HOST=$(grep DB_HOST /home/vagrant/proshop/.env | cut -d'=' -f2)
DB_NAME=$(grep DB_NAME /home/vagrant/proshop/.env | cut -d'=' -f2)

if mysql -u "$DB_USER" -p"$DB_PASSWORD" -h "$DB_HOST" -e "use $DB_NAME;" 2>/dev/null; then
    DB_STATUS="connected"
else
    DB_STATUS="disconnected"
fi

echo "[$TIMESTAMP] CPU: ${CPU}% | RAM: ${RAM}% | DISK: ${DISK}% | nginx: $NGINX | gunicorn: $GUNICORN | db: $DB_STATUS" >> $LOG_FILE

# ===== Email alert function with cooldown (avoids spam) =====
send_alert() {
    local subject="$1"
    local body="$2"
    local alert_key="$3"
    local cooldown_file="/tmp/alert_${alert_key}_sent"
    local cooldown_seconds=1800

    if [ -f "$cooldown_file" ]; then
        local last_sent=$(cat "$cooldown_file")
        local now=$(date +%s)
        if [ $(( now - last_sent )) -lt "$cooldown_seconds" ]; then
            return
        fi
    fi

    echo "Subject: $subject

$body" | msmtp "$ALERT_TO"
    date +%s > "$cooldown_file"
}

if [ "${CPU}" -gt "$CPU_THRESHOLD" ]; then
    echo "[$TIMESTAMP] ALERT: CPU high — ${CPU}%" >> $LOG_FILE
    send_alert "ProShop Alert: High CPU on $(hostname)" "CPU usage is at ${CPU}% (threshold: ${CPU_THRESHOLD}%) at $TIMESTAMP" "cpu_high"
fi

if [ "${RAM}" -gt "$RAM_THRESHOLD" ]; then
    echo "[$TIMESTAMP] ALERT: RAM high — ${RAM}%" >> $LOG_FILE
    send_alert "ProShop Alert: High RAM on $(hostname)" "RAM usage is at ${RAM}% (threshold: ${RAM_THRESHOLD}%) at $TIMESTAMP" "ram_high"
fi

if [ "${DISK}" -gt "$DISK_THRESHOLD" ]; then
    echo "[$TIMESTAMP] ALERT: Disk high — ${DISK}%" >> $LOG_FILE
    send_alert "ProShop Alert: High Disk on $(hostname)" "Disk usage is at ${DISK}% (threshold: ${DISK_THRESHOLD}%) at $TIMESTAMP" "disk_high"
fi

if [ "$NGINX" != "active" ]; then
    echo "[$TIMESTAMP] ALERT: Nginx DOWN" >> $LOG_FILE
    send_alert "ProShop Alert: Nginx DOWN on $(hostname)" "Nginx service is not active at $TIMESTAMP" "nginx_down"
fi

if [ "$GUNICORN" != "active" ] && [ "$GUNICORN" != "N/A" ]; then
    echo "[$TIMESTAMP] ALERT: Gunicorn DOWN" >> $LOG_FILE
    send_alert "ProShop Alert: Gunicorn DOWN on $(hostname)" "Gunicorn service is not active at $TIMESTAMP" "gunicorn_down"
fi

if [ "$DB_STATUS" = "disconnected" ]; then
    echo "[$TIMESTAMP] ALERT: Database unreachable" >> $LOG_FILE
    send_alert "ProShop Alert: Database unreachable" "$(hostname) cannot connect to the database at $TIMESTAMP" "db_down"
fi














































# LOG_FILE="/var/log/proshop_monitor.log"
# TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

# CPU_THRESHOLD=80
# RAM_THRESHOLD=80
# DISK_THRESHOLD=80

# CPU=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'.' -f1)
# RAM=$(free | grep Mem | awk '{printf "%.0f", $3/$2 * 100}')
# DISK=$(df / | tail -1 | awk '{print $5}' | cut -d'%' -f1)
# NGINX=$(systemctl is-active nginx)
# GUNICORN=$(systemctl is-active gunicorn 2>/dev/null || echo "N/A")

# # DB credentials .env se lo — unchanged, grep/cut work identically on CentOS.
# DB_USER=$(grep DB_USER /home/vagrant/proshop/.env | cut -d'=' -f2)
# DB_PASSWORD=$(grep DB_PASSWORD /home/vagrant/proshop/.env | cut -d'=' -f2)
# DB_HOST=$(grep DB_HOST /home/vagrant/proshop/.env | cut -d'=' -f2)
# DB_NAME=$(grep DB_NAME /home/vagrant/proshop/.env | cut -d'=' -f2)

# # CHANGED: nothing here — this connects to MySQL as a remote CLIENT
# # (mysql -h $DB_HOST), not the local mysqld service, so the earlier
# # Ubuntu-vs-CentOS "mysql vs mysqld" service-name difference does not apply
# # in this particular file.
# if mysql -u "$DB_USER" -p"$DB_PASSWORD" -h "$DB_HOST" -e "use $DB_NAME;" 2>/dev/null; then
#     DB_STATUS="connected"
# else
#     DB_STATUS="disconnected"
# fi

# echo "[$TIMESTAMP] CPU: ${CPU}% | RAM: ${RAM}% | DISK: ${DISK}% | nginx: $NGINX | gunicorn: $GUNICORN | db: $DB_STATUS" >> $LOG_FILE

# if [ "${CPU}" -gt "$CPU_THRESHOLD" ]; then
#     echo "[$TIMESTAMP] ALERT: CPU high — ${CPU}%" >> $LOG_FILE
# fi

# if [ "${RAM}" -gt "$RAM_THRESHOLD" ]; then
#     echo "[$TIMESTAMP] ALERT: RAM high — ${RAM}%" >> $LOG_FILE
# fi

# if [ "${DISK}" -gt "$DISK_THRESHOLD" ]; then
#     echo "[$TIMESTAMP] ALERT: Disk high — ${DISK}%" >> $LOG_FILE
# fi

# if [ "$NGINX" != "active" ]; then
#     echo "[$TIMESTAMP] ALERT: Nginx DOWN" >> $LOG_FILE
# fi

# if [ "$GUNICORN" != "active" ] && [ "$GUNICORN" != "N/A" ]; then
#     echo "[$TIMESTAMP] ALERT: Gunicorn DOWN" >> $LOG_FILE
# fi

# if [ "$DB_STATUS" = "disconnected" ]; then
#     echo "[$TIMESTAMP] ALERT: Database unreachable" >> $LOG_FILE
# fi
