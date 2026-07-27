#!/bin/ash
cd /app

# Deliberately not `set -e`: if the account step fails the panel should still come
# up and say why in the log, rather than the container dying and taking the only
# copy of the error with it.

# Runs after the image's entrypoint has migrated and seeded the database.
# Everything here is first-boot only: on later starts the account already exists
# and nothing is touched, so a redeploy does not reset the password.
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

exec supervisord -n -c /etc/supervisord.conf
