#!/bin/bash

# NOTE: This script needed almost NO changes for CentOS Stream 9.
# `top`, `free`, `df`, `systemctl`, and the `mysql` client command all behave
# identically on both distros (procps-ng and the MySQL client are the same
# tools either way) — only the packages providing them differ, and that's
# already handled in web.sh/web2.sh's dnf install line.

LOG_FILE="/var/log/proshop_monitor.log"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

CPU_THRESHOLD=80
RAM_THRESHOLD=80
DISK_THRESHOLD=80

CPU=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'.' -f1)
RAM=$(free | grep Mem | awk '{printf "%.0f", $3/$2 * 100}')
DISK=$(df / | tail -1 | awk '{print $5}' | cut -d'%' -f1)
NGINX=$(systemctl is-active nginx)
GUNICORN=$(systemctl is-active gunicorn 2>/dev/null || echo "N/A")

# DB credentials .env se lo — unchanged, grep/cut work identically on CentOS.
DB_USER=$(grep DB_USER /home/vagrant/proshop/.env | cut -d'=' -f2)
DB_PASSWORD=$(grep DB_PASSWORD /home/vagrant/proshop/.env | cut -d'=' -f2)
DB_HOST=$(grep DB_HOST /home/vagrant/proshop/.env | cut -d'=' -f2)
DB_NAME=$(grep DB_NAME /home/vagrant/proshop/.env | cut -d'=' -f2)

# CHANGED: nothing here — this connects to MySQL as a remote CLIENT
# (mysql -h $DB_HOST), not the local mysqld service, so the earlier
# Ubuntu-vs-CentOS "mysql vs mysqld" service-name difference does not apply
# in this particular file.
if mysql -u "$DB_USER" -p"$DB_PASSWORD" -h "$DB_HOST" -e "use $DB_NAME;" 2>/dev/null; then
    DB_STATUS="connected"
else
    DB_STATUS="disconnected"
fi

echo "[$TIMESTAMP] CPU: ${CPU}% | RAM: ${RAM}% | DISK: ${DISK}% | nginx: $NGINX | gunicorn: $GUNICORN | db: $DB_STATUS" >> $LOG_FILE

if [ "${CPU}" -gt "$CPU_THRESHOLD" ]; then
    echo "[$TIMESTAMP] ALERT: CPU high — ${CPU}%" >> $LOG_FILE
fi

if [ "${RAM}" -gt "$RAM_THRESHOLD" ]; then
    echo "[$TIMESTAMP] ALERT: RAM high — ${RAM}%" >> $LOG_FILE
fi

if [ "${DISK}" -gt "$DISK_THRESHOLD" ]; then
    echo "[$TIMESTAMP] ALERT: Disk high — ${DISK}%" >> $LOG_FILE
fi

if [ "$NGINX" != "active" ]; then
    echo "[$TIMESTAMP] ALERT: Nginx DOWN" >> $LOG_FILE
fi

if [ "$GUNICORN" != "active" ] && [ "$GUNICORN" != "N/A" ]; then
    echo "[$TIMESTAMP] ALERT: Gunicorn DOWN" >> $LOG_FILE
fi

if [ "$DB_STATUS" = "disconnected" ]; then
    echo "[$TIMESTAMP] ALERT: Database unreachable" >> $LOG_FILE
fi
