#!/bin/sh
set -e

# Replace placeholder values with environment variables in HTML files
sed -i "s|__APP_ENV__|${APP_ENV:-development}|g" /usr/share/nginx/html/index.html
sed -i "s|__APP_VERSION__|${APP_VERSION:-v1}|g" /usr/share/nginx/html/index.html
sed -i "s|__APP_NAME__|${APP_NAME:-demo-app}|g" /usr/share/nginx/html/index.html
sed -i "s|__DB_PASSWORD__|${DB_PASSWORD:-not-set}|g" /usr/share/nginx/html/index.html
sed -i "s|__API_KEY__|${API_KEY:-not-set}|g" /usr/share/nginx/html/index.html

# Execute the main command
exec "$@"
