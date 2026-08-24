#!/bin/bash
clear
echo "========================================="
echo "       PROSHOP SERVER STATUS"
echo "========================================="
echo ""

# NOTE: This script itself runs on your HOST laptop (still Ubuntu), not on
# the VMs — so almost nothing here needed to change for the guests moving to
# CentOS Stream 9. `top`, `free`, `df`, and `systemctl is-active` all produce
# identical output whether the remote guest is Ubuntu or CentOS. The ONLY
# change required is the MySQL service name check below, since that service
# is now literally named differently on the DB guest.

WEB_KEY="/home/dheeraj/devops-vms/centos_multivms/.vagrant/machines/web/virtualbox/private_key"
WEB2_KEY="/home/dheeraj/devops-vms/centos_multivms/.vagrant/machines/web2/virtualbox/private_key"
DB_KEY="/home/dheeraj/devops-vms/centos_multivms/.vagrant/machines/db/virtualbox/private_key"
LB_KEY="/home/dheeraj/devops-vms/centos_multivms/.vagrant/machines/lb/virtualbox/private_key"

SSH_OPTS="-o StrictHostKeyChecking=no -o ConnectTimeout=5"

echo "--- WEB SERVER (192.168.56.11) ---"
ssh $SSH_OPTS -i $WEB_KEY vagrant@192.168.56.11 "
CPU=\$(top -bn1 | grep 'Cpu(s)' | awk '{print \$2}' | cut -d'.' -f1)
RAM=\$(free | grep Mem | awk '{printf \"%.0f\", \$3/\$2 * 100}')
DISK=\$(df / | tail -1 | awk '{print \$5}')
NGINX=\$(systemctl is-active nginx)
GUNICORN=\$(systemctl is-active gunicorn)
echo \"CPU: \${CPU}% | RAM: \${RAM}% | Disk: \${DISK}\"
echo \"Nginx: \$NGINX | Gunicorn: \$GUNICORN\"
"

echo ""
echo "--- WEB2 SERVER (192.168.56.13) ---"
ssh $SSH_OPTS -i $WEB2_KEY vagrant@192.168.56.13 "
CPU=\$(top -bn1 | grep 'Cpu(s)' | awk '{print \$2}' | cut -d'.' -f1)
RAM=\$(free | grep Mem | awk '{printf \"%.0f\", \$3/\$2 * 100}')
DISK=\$(df / | tail -1 | awk '{print \$5}')
NGINX=\$(systemctl is-active nginx)
GUNICORN=\$(systemctl is-active gunicorn)
echo \"CPU: \${CPU}% | RAM: \${RAM}% | Disk: \${DISK}\"
echo \"Nginx: \$NGINX | Gunicorn: \$GUNICORN\"
"

echo ""
echo "--- DB SERVER (192.168.56.12) ---"
ssh $SSH_OPTS -i $DB_KEY vagrant@192.168.56.12 "
CPU=\$(top -bn1 | grep 'Cpu(s)' | awk '{print \$2}' | cut -d'.' -f1)
RAM=\$(free | grep Mem | awk '{printf \"%.0f\", \$3/\$2 * 100}')
DISK=\$(df / | tail -1 | awk '{print \$5}')
MYSQL=\$(systemctl is-active mysqld)
echo \"CPU: \${CPU}% | RAM: \${RAM}% | Disk: \${DISK}\"
echo \"MySQL: \$MYSQL\"
"
# CHANGED: 'systemctl is-active mysql' -> 'systemctl is-active mysqld'
# The DB VM's service is literally named "mysqld" on CentOS/RHEL, not
# "mysql" like on Ubuntu/Debian — this line would otherwise always print
# "unknown" / a non-zero exit even though MySQL is running fine.

echo ""
echo "--- LOAD BALANCER (192.168.56.10) ---"
ssh $SSH_OPTS -i $LB_KEY vagrant@192.168.56.10 "
CPU=\$(top -bn1 | grep 'Cpu(s)' | awk '{print \$2}' | cut -d'.' -f1)
RAM=\$(free | grep Mem | awk '{printf \"%.0f\", \$3/\$2 * 100}')
DISK=\$(df / | tail -1 | awk '{print \$5}')
NGINX=\$(systemctl is-active nginx)
echo \"CPU: \${CPU}% | RAM: \${RAM}% | Disk: \${DISK}\"
echo \"Nginx: \$NGINX\"
"

echo ""
echo "--- RECENT ALERTS ---"
ssh $SSH_OPTS -i $WEB_KEY vagrant@192.168.56.11 \
    "grep 'ALERT' /var/log/proshop_monitor.log 2>/dev/null | tail -5 || echo 'No alerts'"

echo ""
echo "========================================="
echo "Last checked: $(date)"
echo "========================================="
