#!/bin/bash

# NOTE: No functional changes needed for CentOS Stream 9 in this file.
# `top`, `free`, `df`, `systemctl`, and `curl` all behave identically —
# curl is explicitly installed via dnf in lb.sh's provisioning step to
# guarantee it's present (CentOS minimal images sometimes ship only
# curl-minimal, but it provides the same `curl` binary/flags used here).

#!/bin/bash
# lb_monitor.sh — for Load Balancer VM (192.168.56.10)
# Same email-alert + cooldown pattern as web servers' monitor.sh, but checks
# LB's own Nginx health PLUS whether Web1/Web2 are reachable from the LB's
# point of view (this is the LB's actual job — detect upstream failures).

LOG_FILE="/var/log/lb_monitor.log"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

ALERT_TO="dheeraj.chelani2005@gmail.com"

CPU=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'.' -f1)
RAM=$(free | grep Mem | awk '{printf "%.0f", $3/$2 * 100}')
DISK=$(df / | tail -1 | awk '{print $5}' | cut -d'%' -f1)
NGINX=$(systemctl is-active nginx)

WEB1=$(curl -s -o /dev/null -w "%{http_code}" http://192.168.56.11 --max-time 3)
WEB2=$(curl -s -o /dev/null -w "%{http_code}" http://192.168.56.13 --max-time 3)

echo "[$TIMESTAMP] CPU: ${CPU}% | RAM: ${RAM}% | DISK: ${DISK}% | nginx: $NGINX | web1: $WEB1 | web2: $WEB2" >> $LOG_FILE

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

if [ "$NGINX" != "active" ]; then
    echo "[$TIMESTAMP] ALERT: LB Nginx DOWN" >> $LOG_FILE
    send_alert "ProShop Alert: Load Balancer Nginx DOWN" "Nginx on the load balancer ($(hostname)) is not active at $TIMESTAMP" "lb_nginx_down"
fi

if [ "$WEB1" != "200" ]; then
    echo "[$TIMESTAMP] ALERT: Web1 unreachable — HTTP $WEB1" >> $LOG_FILE
    send_alert "ProShop Alert: Web1 unreachable" "Web1 (192.168.56.11) returned HTTP $WEB1 at $TIMESTAMP. It may be down or Gunicorn/Nginx has crashed on that VM." "web1_down"
fi

if [ "$WEB2" != "200" ]; then
    echo "[$TIMESTAMP] ALERT: Web2 unreachable — HTTP $WEB2" >> $LOG_FILE
    send_alert "ProShop Alert: Web2 unreachable" "Web2 (192.168.56.13) returned HTTP $WEB2 at $TIMESTAMP. It may be down or Gunicorn/Nginx has crashed on that VM." "web2_down"
fi

# Bonus: if BOTH web servers are down, this is a total outage — worth a
# distinct, more urgent-sounding alert instead of just two separate emails.
if [ "$WEB1" != "200" ] && [ "$WEB2" != "200" ]; then
    echo "[$TIMESTAMP] CRITICAL: Both web servers unreachable — total outage" >> $LOG_FILE
    send_alert "🚨 ProShop CRITICAL: Total outage — both web servers down" "Neither Web1 nor Web2 is responding as of $TIMESTAMP. The site is fully down." "total_outage"
fi
























# LOG_FILE="/var/log/lb_monitor.log"
# TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

# CPU=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'.' -f1)
# RAM=$(free | grep Mem | awk '{printf "%.0f", $3/$2 * 100}')
# DISK=$(df / | tail -1 | awk '{print $5}' | cut -d'%' -f1)
# NGINX=$(systemctl is-active nginx)

# WEB1=$(curl -s -o /dev/null -w "%{http_code}" http://192.168.56.11 --max-time 3)
# WEB2=$(curl -s -o /dev/null -w "%{http_code}" http://192.168.56.13 --max-time 3)

# echo "[$TIMESTAMP] CPU: ${CPU}% | RAM: ${RAM}% | DISK: ${DISK}% | nginx: $NGINX | web1: $WEB1 | web2: $WEB2" >> $LOG_FILE

# if [ "$NGINX" != "active" ]; then
#     echo "[$TIMESTAMP] ALERT: LB Nginx DOWN" >> $LOG_FILE
# fi

# if [ "$WEB1" != "200" ]; then
#     echo "[$TIMESTAMP] ALERT: Web1 unreachable — HTTP $WEB1" >> $LOG_FILE
# fi

# if [ "$WEB2" != "200" ]; then
#     echo "[$TIMESTAMP] ALERT: Web2 unreachable — HTTP $WEB2" >> $LOG_FILE
# fi
