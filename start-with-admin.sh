#!/bin/ash
cd /app

# Deliberately not `set -e`: if the account step fails the panel should still come
# up and say why in the log, rather than the container dying and taking the only
# copy of the error with it.

# The image's entrypoint migrates before handing off here, but its readiness
# check is a bare TCP connect against the database host. On a brand new
# MariaDB volume the port can accept connections before MariaDB has finished
# creating its own database and user from MARIADB_DATABASE/MARIADB_USER, so
# on that very first boot a handful of migrations can silently fail to apply
# while others succeed - enough for the users table to exist (so the admin
# account gets created below) but not enough for login to work, which fails
# with a generic QueryException until the next deploy. Migrations are
# idempotent, so re-running here is a no-op on every later boot and closes
# that race on the first one.
php artisan migrate --force --no-interaction 2>&1 | tail -5

# Runs after the migration above. Everything past this point is first-boot
# only: on later starts the account already exists and nothing is touched,
# so a redeploy does not reset the password.
if [ -n "$ADMIN_EMAIL" ] && [ -n "$ADMIN_PASSWORD" ]; then
  USERS=$(php artisan tinker --execute="echo \App\Models\User::count();" 2>/dev/null | tail -n1 | tr -dc '0-9')

  if [ "${USERS:-0}" = "0" ]; then
    echo "Creating the first administrator."
    php artisan p:user:make \
      --email="$ADMIN_EMAIL" \
      --username="${ADMIN_USERNAME:-admin}" \
      --name-first="${ADMIN_FIRST_NAME:-Panel}" \
      --name-last="${ADMIN_LAST_NAME:-Administrator}" \
      --password="$ADMIN_PASSWORD" \
      --admin=1 \
      --no-interaction
    echo "Administrator created: $ADMIN_EMAIL"
  else
    echo "Users already exist ($USERS) - leaving the account list alone."
  fi
else
  # Without this the panel comes up with an empty user table and no way in
  # except a shell into the container.
  echo "ADMIN_EMAIL or ADMIN_PASSWORD is not set - no administrator will be created." >&2
fi

# The panel's nginx config hardcodes port 80. A platform assigns a port instead,
# and the assignment does not always survive being packaged into a template - so
# the port is rewritten here from the environment rather than relied upon.
LISTEN_PORT="${PORT:-80}"
if [ -f /etc/nginx/http.d/panel.conf ]; then
  sed -i "s/listen  *80;/listen ${LISTEN_PORT};/" /etc/nginx/http.d/panel.conf
  echo "nginx listening on ${LISTEN_PORT}"
fi

exec supervisord -n -c /etc/supervisord.conf
