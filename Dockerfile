# Pinned. The stock template uses :latest, so two deploys a month apart are not
# the same panel - and this one encrypts data with a key it stores on disk.
FROM ghcr.io/pterodactyl/panel:v1.14.1

COPY start-with-admin.sh /usr/local/bin/start-with-admin.sh
RUN chmod +x /usr/local/bin/start-with-admin.sh

# The image's own entrypoint ends with `exec "$@"`, after it has waited for the
# database and run the migrations. Replacing the command - rather than the
# entrypoint - is therefore the one place a first-boot step can run with a
# migrated database, without reimplementing any of Pterodactyl's own setup.
CMD ["/usr/local/bin/start-with-admin.sh"]
