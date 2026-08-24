#!/bin/bash

# NOTE: No functional changes needed for CentOS Stream 9 in this file.
# `top`, `free`, `df`, `systemctl`, and `curl` all behave identically —
# curl is explicitly installed via dnf in lb.sh's provisioning step to
# guarantee it's present (CentOS minimal images sometimes ship only
# curl-minimal, but it provides the same `curl` binary/flags used here).

LOG_FILE="/var/log/lb_monitor.log"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

CPU=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'.' -f1)
RAM=$(free | grep Mem | awk '{printf "%.0f", $3/$2 * 100}')
DISK=$(df / | tail -1 | awk '{print $5}' | cut -d'%' -f1)
NGINX=$(systemctl is-active nginx)

WEB1=$(curl -s -o /dev/null -w "%{http_code}" http://192.168.56.11 --max-time 3)
WEB2=$(curl -s -o /dev/null -w "%{http_code}" http://192.168.56.13 --max-time 3)

echo "[$TIMESTAMP] CPU: ${CPU}% | RAM: ${RAM}% | DISK: ${DISK}% | nginx: $NGINX | web1: $WEB1 | web2: $WEB2" >> $LOG_FILE

if [ "$NGINX" != "active" ]; then
    echo "[$TIMESTAMP] ALERT: LB Nginx DOWN" >> $LOG_FILE
fi

if [ "$WEB1" != "200" ]; then
    echo "[$TIMESTAMP] ALERT: Web1 unreachable — HTTP $WEB1" >> $LOG_FILE
fi

if [ "$WEB2" != "200" ]; then
    echo "[$TIMESTAMP] ALERT: Web2 unreachable — HTTP $WEB2" >> $LOG_FILE
fi
