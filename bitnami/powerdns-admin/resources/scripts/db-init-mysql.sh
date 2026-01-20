#!/bin/bash
# Copyright Anthropic. All Rights Reserved.
# SPDX-License-Identifier: APACHE-2.0
#
# MySQL database initialization script for PowerDNS-Admin
# This script creates the database and user if they don't exist

set -e

# Configuration from environment
MAX_RETRIES="${MAX_RETRIES:-15}"
RETRY_INTERVAL="${RETRY_INTERVAL:-5}"

DB_HOST="${DB_HOST}"
DB_PORT="${DB_PORT:-3306}"
DB_ADMIN_USER="${DB_ADMIN_USER:-root}"
DB_ADMIN_PASS="${DB_ADMIN_PASS}"

DB_NAME="${DB_NAME}"
DB_USER="${DB_USER}"
DB_PASS="${DB_USER_PASS}"

MYSQL_ADMIN="mysql -h ${DB_HOST} -P ${DB_PORT} -u ${DB_ADMIN_USER} -p${DB_ADMIN_PASS}"

echo "========================================"
echo "PowerDNS-Admin MySQL Database Init"
echo "========================================"
echo "Host: ${DB_HOST}:${DB_PORT}"
echo "Database: ${DB_NAME}"
echo "User: ${DB_USER}"
echo "========================================"

# Wait for MySQL connection
echo "Waiting for MySQL connection..."
attempts=0
while ! ${MYSQL_ADMIN} -e 'SELECT 1' >/dev/null 2>&1; do
    if [ "${attempts}" -ge "${MAX_RETRIES}" ]; then
        echo "ERROR: Unable to connect to MySQL after ${MAX_RETRIES} attempts"
        exit 1
    fi
    echo "Attempt $((attempts + 1))/${MAX_RETRIES}: Waiting for MySQL..."
    sleep $((attempts * RETRY_INTERVAL / 3 + RETRY_INTERVAL))
    attempts=$((attempts + 1))
done

echo "MySQL connection established"

# Create database if not exists
echo "Creating database ${DB_NAME} if not exists..."
${MYSQL_ADMIN} -e "CREATE DATABASE IF NOT EXISTS \`${DB_NAME}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"

# Create user and grant privileges
echo "Creating user ${DB_USER} if not exists..."
${MYSQL_ADMIN} -e "CREATE USER IF NOT EXISTS '${DB_USER}'@'%' IDENTIFIED BY '${DB_PASS}';"
${MYSQL_ADMIN} -e "GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO '${DB_USER}'@'%';"
${MYSQL_ADMIN} -e "FLUSH PRIVILEGES;"

echo "========================================"
echo "MySQL database initialization completed successfully"
echo "========================================"
