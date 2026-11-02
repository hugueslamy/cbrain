# CBRAIN SSH key for Docker development

The portal uses this key pair to SSH to the Bourreau container.
It is mounted into both containers by `docker-compose.yml`; the key files
themselves are ignored by git.

Create it once, from the repository root, **before** the first `docker compose up`
(otherwise Docker creates empty directories in place of the missing files):

```bash
ssh-keygen -t ed25519 -N '' -C CBRAIN_Portal_Key -f docker/ssh/id_cbrain_ed25519
```

The portal's `known_hosts` is kept in the `portal_ssh` volume and the
Bourreau's host keys in `bourreau_hostkeys`, so both survive rebuilds.
To start over with new host keys, remove both volumes:

```bash
docker compose down
docker volume rm cbrain_portal_ssh cbrain_bourreau_hostkeys
```
