#!/bin/bash
# db_monitor.sh — for Database VM (192.168.56.12)
#
# WHY THIS SCRIPT NEEDED TO EXIST:
# Right now Web1, Web2, and the LB all get monitored — but the DB VM itself
# has zero visibility. If MySQL's own CPU/RAM/disk gets stressed, or mysqld
# crashes, you'd only find out indirectly (web servers' "db: disconnected"
# alert) — you wouldn't know if it's a DB-VM problem or a network problem
# between VMs. This script closes that blind spot.

LOG_FILE="/var/log/db_monitor.log"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

CPU_THRESHOLD=1
RAM_THRESHOLD=2
DISK_THRESHOLD=3
CONN_THRESHOLD=4   # percentage of max_connections in use

ALERT_TO="dheeraj.chelani2005@gmail.com"

CPU=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'.' -f1)
RAM=$(free | grep Mem | awk '{printf "%.0f", $3/$2 * 100}')
DISK=$(df / | tail -1 | awk '{print $5}' | cut -d'%' -f1)
MYSQLD=$(systemctl is-active mysqld)

# Connection-usage check — this is DB-specific and doesn't apply to web
# servers, so it lives only here. Recall from the crash-scenario discussion:
# if too many connections pile up (e.g. a connection leak on the web tier),
# MySQL starts rejecting new ones — this catches that BEFORE it becomes a
# site-wide outage.
CONN_PCT="N/A"
if [ "$MYSQLD" = "active" ]; then
    MAX_CONN=$(mysql -N -e "SHOW VARIABLES LIKE 'max_connections';" 2>/dev/null | awk '{print $2}')
    CUR_CONN=$(mysql -N -e "SHOW STATUS LIKE 'Threads_connected';" 2>/dev/null | awk '{print $2}')
    if [ -n "$MAX_CONN" ] && [ -n "$CUR_CONN" ] && [ "$MAX_CONN" -gt 0 ]; then
        CONN_PCT=$(( CUR_CONN * 100 / MAX_CONN ))
    fi
fi

echo "[$TIMESTAMP] CPU: ${CPU}% | RAM: ${RAM}% | DISK: ${DISK}% | mysqld: $MYSQLD | connections: ${CONN_PCT}%" >> $LOG_FILE

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
    send_alert "ProShop Alert: High CPU on DB server" "CPU usage is at ${CPU}% (threshold: ${CPU_THRESHOLD}%) at $TIMESTAMP" "db_cpu_high"
fi

if [ "${RAM}" -gt "$RAM_THRESHOLD" ]; then
    echo "[$TIMESTAMP] ALERT: RAM high — ${RAM}%" >> $LOG_FILE
    send_alert "ProShop Alert: High RAM on DB server" "RAM usage is at ${RAM}% (threshold: ${RAM_THRESHOLD}%) at $TIMESTAMP" "db_ram_high"
fi

if [ "${DISK}" -gt "$DISK_THRESHOLD" ]; then
    echo "[$TIMESTAMP] ALERT: Disk high — ${DISK}%" >> $LOG_FILE
    send_alert "ProShop Alert: High Disk on DB server" "Disk usage is at ${DISK}% (threshold: ${DISK_THRESHOLD}%) at $TIMESTAMP" "db_disk_high"
fi

if [ "$MYSQLD" != "active" ]; then
    echo "[$TIMESTAMP] ALERT: mysqld DOWN" >> $LOG_FILE
    send_alert "🚨 ProShop CRITICAL: MySQL is DOWN" "mysqld service is not active on the DB server at $TIMESTAMP. All web servers will lose database connectivity." "mysqld_down"
fi

if [ "$CONN_PCT" != "N/A" ] && [ "$CONN_PCT" -gt "$CONN_THRESHOLD" ]; then
    echo "[$TIMESTAMP] ALERT: Connection usage high — ${CONN_PCT}%" >> $LOG_FILE
    send_alert "ProShop Alert: DB connection usage high" "MySQL is using ${CONN_PCT}% of max_connections (threshold: ${CONN_THRESHOLD}%) at $TIMESTAMP. Check for connection leaks on the web tier." "db_conn_high"
fi
