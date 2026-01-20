#!/bin/bash
# Copyright Anthropic. All Rights Reserved.
# SPDX-License-Identifier: APACHE-2.0
#
# PostgreSQL database initialization script for PowerDNS-Admin
# This script creates the database and user if they don't exist

set -e

# Configuration from environment
MAX_RETRIES="${MAX_RETRIES:-15}"
RETRY_INTERVAL="${RETRY_INTERVAL:-5}"

export PGHOST="${DB_HOST}"
export PGPORT="${DB_PORT:-5432}"
export PGUSER="${DB_ADMIN_USER:-postgres}"
export PGPASSWORD="${DB_ADMIN_PASS}"

DB_NAME="${DB_NAME}"
DB_USER="${DB_USER}"
DB_PASS="${DB_USER_PASS}"

echo "========================================"
echo "PowerDNS-Admin PostgreSQL Database Init"
echo "========================================"
echo "Host: ${PGHOST}:${PGPORT}"
echo "Database: ${DB_NAME}"
echo "User: ${DB_USER}"
echo "========================================"

# Wait for PostgreSQL connection
echo "Waiting for PostgreSQL connection..."
attempts=0
while ! psql -c 'SELECT 1' >/dev/null 2>&1; do
    if [ "${attempts}" -ge "${MAX_RETRIES}" ]; then
        echo "ERROR: Unable to connect to PostgreSQL after ${MAX_RETRIES} attempts"
        exit 1
    fi
    echo "Attempt $((attempts + 1))/${MAX_RETRIES}: Waiting for PostgreSQL..."
    sleep $((attempts * RETRY_INTERVAL / 3 + RETRY_INTERVAL))
    attempts=$((attempts + 1))
done

echo "PostgreSQL connection established"

# Create user if not exists
echo "Creating user ${DB_USER} if not exists..."
if psql -tc "SELECT 1 FROM pg_roles WHERE rolname='${DB_USER}'" | grep -q 1; then
    echo "User ${DB_USER} already exists"
else
    psql -c "CREATE USER ${DB_USER} WITH PASSWORD '${DB_PASS}';"
    echo "User ${DB_USER} created"
fi

# Create database if not exists
echo "Creating database ${DB_NAME} if not exists..."
if psql -tc "SELECT 1 FROM pg_database WHERE datname='${DB_NAME}'" | grep -q 1; then
    echo "Database ${DB_NAME} already exists"
else
    psql -c "CREATE DATABASE ${DB_NAME} OWNER ${DB_USER};"
    echo "Database ${DB_NAME} created"
fi

# Grant privileges
echo "Granting privileges..."
psql -c "GRANT ALL PRIVILEGES ON DATABASE ${DB_NAME} TO ${DB_USER};"

# Grant schema privileges (PostgreSQL 15+)
echo "Granting schema privileges..."
psql -d "${DB_NAME}" -c "GRANT ALL ON SCHEMA public TO ${DB_USER};" 2>/dev/null || true

echo "========================================"
echo "PostgreSQL database initialization completed successfully"
echo "========================================"
