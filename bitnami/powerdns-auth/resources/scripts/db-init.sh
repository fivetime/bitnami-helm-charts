#!/bin/bash
set -e

MAX_RETRIES={{ .Values.database.connection.maxRetries }}
RETRY_INTERVAL={{ .Values.database.connection.retryInterval }}

{{- if eq .Values.database.type "mysql" }}
# MySQL database initialization
DB_HOST="{{ include "powerdns-auth.databaseHost" . }}"
DB_PORT="{{ include "powerdns-auth.databasePort" . }}"
DB_NAME="{{ include "powerdns-auth.databaseName" . }}"
DB_ADMIN_USER="${DB_ADMIN_USER:-root}"
DB_ADMIN_PASS="${DB_ADMIN_PASS}"
DB_USER="{{ include "powerdns-auth.databaseUsername" . }}"
DB_PASS="${DB_USER_PASS}"

MYSQL_ADMIN="mysql -h ${DB_HOST} -P ${DB_PORT} -u ${DB_ADMIN_USER} -p${DB_ADMIN_PASS}"

echo "Waiting for MySQL connection..."
attempts=0
while ! ${MYSQL_ADMIN} -e 'SELECT 1' >/dev/null 2>&1; do
    if [ "${attempts}" -ge "${MAX_RETRIES}" ]; then
        echo "ERROR: Unable to connect to MySQL after ${MAX_RETRIES} attempts"
        exit 1
    fi
    echo "Attempt ${attempts}/${MAX_RETRIES}: Waiting for MySQL..."
    sleep $((attempts * RETRY_INTERVAL / 3 + RETRY_INTERVAL))
    attempts=$((attempts + 1))
done

echo "MySQL connection established"

# Create database if not exists (idempotent)
echo "Creating database ${DB_NAME} if not exists..."
${MYSQL_ADMIN} -e "CREATE DATABASE IF NOT EXISTS \`${DB_NAME}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"

# Create user if not exists and grant privileges (idempotent)
echo "Creating user ${DB_USER} if not exists..."
${MYSQL_ADMIN} -e "CREATE USER IF NOT EXISTS '${DB_USER}'@'%' IDENTIFIED BY '${DB_PASS}';"
${MYSQL_ADMIN} -e "GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO '${DB_USER}'@'%';"
${MYSQL_ADMIN} -e "FLUSH PRIVILEGES;"

echo "MySQL database initialization completed"
{{- else }}
# PostgreSQL database initialization
export PGHOST="{{ include "powerdns-auth.databaseHost" . }}"
export PGPORT="{{ include "powerdns-auth.databasePort" . }}"
export PGUSER="${DB_ADMIN_USER:-postgres}"
export PGPASSWORD="${DB_ADMIN_PASS}"

DB_NAME="{{ include "powerdns-auth.databaseName" . }}"
DB_USER="{{ include "powerdns-auth.databaseUsername" . }}"
DB_PASS="${DB_USER_PASS}"

echo "Waiting for PostgreSQL connection..."
attempts=0
while ! psql -c 'SELECT 1' >/dev/null 2>&1; do
    if [ "${attempts}" -ge "${MAX_RETRIES}" ]; then
        echo "ERROR: Unable to connect to PostgreSQL after ${MAX_RETRIES} attempts"
        exit 1
    fi
    echo "Attempt ${attempts}/${MAX_RETRIES}: Waiting for PostgreSQL..."
    sleep $((attempts * RETRY_INTERVAL / 3 + RETRY_INTERVAL))
    attempts=$((attempts + 1))
done

echo "PostgreSQL connection established"

# Create user if not exists (idempotent)
echo "Creating user ${DB_USER} if not exists..."
psql -tc "SELECT 1 FROM pg_roles WHERE rolname='${DB_USER}'" | grep -q 1 || \
    psql -c "CREATE USER ${DB_USER} WITH PASSWORD '${DB_PASS}';"

# Create database if not exists (idempotent)
echo "Creating database ${DB_NAME} if not exists..."
psql -tc "SELECT 1 FROM pg_database WHERE datname='${DB_NAME}'" | grep -q 1 || \
    psql -c "CREATE DATABASE ${DB_NAME} OWNER ${DB_USER};"

# Grant privileges (idempotent)
echo "Granting privileges..."
psql -c "GRANT ALL PRIVILEGES ON DATABASE ${DB_NAME} TO ${DB_USER};"

echo "PostgreSQL database initialization completed"
{{- end }}
