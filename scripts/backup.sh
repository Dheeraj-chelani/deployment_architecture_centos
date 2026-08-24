#!/bin/bash

# NOTE: No functional changes needed for CentOS Stream 9 in this file.
# `mysqldump` ships as part of the `mysql` client package on RHEL9 (installed
# via dnf in web.sh), exactly like it does with mysql-client on Ubuntu — same
# binary name, same flags, same behaviour. The shared /vagrant folder also
# works identically across both guest OSes since it's a VirtualBox shared
# folder feature, not an OS-level one.

BACKUP_DIR="/vagrant/backups"
TIMESTAMP=$(date '+%Y%m%d_%H%M%S')
BACKUP_FILE="$BACKUP_DIR/proshop_$TIMESTAMP.sql"
KEEP_DAYS=7

# Credentials .env se lo
DB_USER=$(grep DB_USER /home/vagrant/proshop/.env | cut -d'=' -f2)
DB_PASSWORD=$(grep DB_PASSWORD /home/vagrant/proshop/.env | cut -d'=' -f2)
DB_HOST=$(grep DB_HOST /home/vagrant/proshop/.env | cut -d'=' -f2)
DB_NAME=$(grep DB_NAME /home/vagrant/proshop/.env | cut -d'=' -f2)

mkdir -p "$BACKUP_DIR"

mysqldump -u "$DB_USER" -p"$DB_PASSWORD" -h "$DB_HOST" "$DB_NAME" > "$BACKUP_FILE"

if [ $? -eq 0 ]; then
    echo "[$(date)] Backup successful: $BACKUP_FILE" >> /var/log/proshop_backup.log
    gzip "$BACKUP_FILE"
else
    echo "[$(date)] Backup FAILED" >> /var/log/proshop_backup.log
fi

find "$BACKUP_DIR" -name "*.sql.gz" -mtime +$KEEP_DAYS -delete

echo "[$(date)] Old backups cleaned up" >> /var/log/proshop_backup.log
