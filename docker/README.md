# CBRAIN development environment (Docker)

A complete CBRAIN on your machine: the portal and a Bourreau, optionally
with a small emulated HPC cluster (Slurm, Lmod modules, Apptainer). It is
meant for developing and testing tools: you add a Boutiques descriptor,
launch a task from the portal, and it goes through the path a real
installation uses (SSH, task setup, execution, results saved back).
It is not sized for real workloads.

## Two setups

| Setup | Bourreau | Where the tasks run | Containers |
|-------|----------|---------------------|------------|
| **unix** (default) | `bourreau_unix`, cluster type UNIX | In the Bourreau container | 5 |
| **slurm** | `bourreau_slurm`, cluster type SLURM | Submitted with `sbatch` to compute node `c1`, as on an HPC ([slurm/README.md](slurm/README.md)) | 9 |

Start with **unix**: it is lighter and enough to develop a tool. Use
**slurm** to test what a cluster adds: job submission, modules, a compute
node that sees only the shared filesystem.

The setup is chosen in `docker-compose.yml` at the repository root: keep one
`include` line uncommented.

```yaml
include:
  - docker-compose.unix.yml
# - path: [docker-compose.unix.yml, docker-compose.slurm.yml]
```

`docker-compose.unix.yml` defines every service of the unix setup;
`docker-compose.slurm.yml` is merged over it and adds the cluster.

| Service     | Setup | Role                                                       |
|-------------|-------|------------------------------------------------------------|
| `web`       | both  | BrainPortal (Rails), <http://localhost:3000>               |
| `db`        | both  | MariaDB for CBRAIN (`cbrain_dev`, and `cbrain_test` for specs) |
| `bourreau`  | both  | The Bourreau; with slurm, also the cluster's login node    |
| `test`      | both  | Idle container for running the RSpec suite                 |
| `adminer`   | both  | Database browser, <http://127.0.0.1:8080>                  |
| `slurmctld`, `slurmdbd`, `slurmdb` | slurm | Slurm controller and accounting  |
| `c1`        | slurm | Slurm compute node, where the jobs run                     |

## Requirements

- Linux with Docker Engine and the Compose plugin (`docker compose`,
  version 2.20 or later for `include`).
- The container that runs the tasks is privileged: `bourreau` with unix,
  `c1` with slurm. Apptainer needs it in Docker
  (see [slurm/README.md](slurm/README.md#limits)).
- Network access on the first start: gems, and container images for tools.

## Installation

From the root of the repository:

1. **Choose the setup** in `docker-compose.yml` (see [Two setups](#two-setups)).

2. **Create the SSH key** the portal uses to reach the Bourreau. Do this
   before the first `up`, or Docker creates empty directories in place of the
   key files ([ssh/README.md](ssh/README.md)):

   ```bash
   ssh-keygen -t ed25519 -N '' -C CBRAIN_Portal_Key -f docker/ssh/id_cbrain_ed25519
   ```

3. **Build and start everything:**

   ```bash
   docker compose build
   docker compose up -d
   ```

4. **Wait for the portal.** The first start prepares the database (see
   [What happens at each start](#what-happens-at-each-start)); follow it with
   `docker compose logs -f web` until you see `Listening on http://0.0.0.0:3000`.

5. **Get the admin password.** It is generated on the first start only:

   ```bash
   docker compose logs web | grep "admin password"
   ```

   Log in at <http://localhost:3000> as `admin`; you must change the password
   at the first login.

6. **Start the Bourreau.** In the portal, open **Servers**, check
   `bourreau_unix` (or `bourreau_slurm`), then in **Start Services** click
   **2. Start Execution Server**, then **3a. Start Task Workers**.
   Do this again after every restart of the containers.

That's it: the Bourreau, its Data Provider and the tools of the installed
plugins are already configured. Add a tool with
[Developing a tool](#developing-a-tool).

## What happens at each start

Nothing needs to be run by hand. The portal's entrypoint
(`BrainPortal/bin/docker-entrypoint`), before starting the server, runs:

| Step | What it does |
|------|--------------|
| `bundle install` (if needed) | `Gemfile.lock` is not in git; installs what the app's bundle needs |
| `rake db:prepare` | New database: loads the schema and runs `db/seeds.rb` (admin user, portal record). Existing one: runs pending migrations |
| `rake db:sanity:check` | Required: the portal refuses to boot until it has run |
| `rake cbrain:plugins:install:all` | Links the plugins found in `BrainPortal/cbrain_plugins/` (the Bourreau shares that directory) |
| `rake db:seed:docker` | Creates the setup's Bourreau and the Data Provider `bourreau_data` (`db/seeds_docker.rb`) |

Every step is idempotent. `db:seed:docker` only creates missing records:
changes you make in the portal (for example the Bourreau's settings) are kept.
At boot, the Bourreau creates a ToolConfig for each Boutiques descriptor,
using the descriptor's `container-image` when it has one.

The `test` container prepares `cbrain_test` the same way at each start
(`db:prepare`, `db:sanity:check`). The `db` container creates `cbrain_test`
when its volume is new (`docker/db/initdb`).

## What is preconfigured

| Record | Settings |
|--------|----------|
| Bourreau `bourreau_unix` or `bourreau_slurm` | Host `bourreau`, user `cbrain`, Rails directory `/cbrain/Bourreau`, cluster type UNIX or SLURM, Apptainer executable `apptainer`, cache `/home/cbrain/data/<name>/cache`, work directories `/home/cbrain/data/<name>/work` |
| Data Provider `bourreau_data` | SSH to `cbrain@bourreau:/home/cbrain/data/dp`, in the `bourreau_data` volume; put your test files there |
| Portal `cbrain_portal` | Data Provider cache `/home/cbrain/data/cache` |

## Switching setups

The two setups share the database and the volumes, so your users, files and
tasks are kept:

```bash
docker compose down      # without -v
# edit docker-compose.yml: uncomment the other include line
docker compose up -d
```

Run `down` before editing: afterwards, Compose no longer knows the services
of the previous setup and leaves them running. Then start the setup's
Bourreau (installation step 6). The portal creates its record at the first
start; the other Bourreau's record stays, stopped, with its own cache and
work directories. Tasks run on one Bourreau are not moved to the other.

## Developing a tool

1. Put your plugin in `BrainPortal/cbrain_plugins/<your-plugin>/`, with your
   descriptor in `boutiques_descriptors/` (the same layout as
   `cbrain-plugins-base`).
2. Restart the portal, `docker compose restart web`, and start the Bourreau
   again (installation step 6). The portal links the plugin, and the
   Bourreau creates its ToolConfig.
3. Provide the tool's software: give the descriptor a `container-image`,
   which Apptainer runs (both setups). With slurm, it can also be a module
   on `c1`. See [slurm/README.md](slurm/README.md#providing-a-tools-software).
4. Add an input file: copy it into the `bourreau_data` Data Provider
   (`docker compose cp myvideo.mp4 bourreau:/home/cbrain/data/dp/`, then
   `docker compose exec bourreau chown cbrain:cbrain /home/cbrain/data/dp/myvideo.mp4`),
   and register it in the portal (**Data Providers**, `bourreau_data`, **Browse**).
5. Launch the task from the portal and follow it in **Tasks**.

## Daily use

```bash
docker compose up -d                 # start (then start the Bourreau, step 6)
docker compose stop                  # stop, keeping everything
docker compose logs -f web           # portal log (also: bourreau, c1, slurmctld...)
docker compose exec web bundle exec rails console        # portal console
docker compose exec test bundle exec rspec               # RSpec suite
docker compose exec test bundle exec rspec spec/models/tool_spec.rb
docker compose exec -u cbrain bourreau bash -l           # shell in the Bourreau container
```

Bourreau console: from a portal console, `Bourreau.console("bourreau_unix")`
(or `"bourreau_slurm"`). Bourreau logs are in `Bourreau/log/` of your
checkout (`TaskWorkers.combined.log` shows each task's setup, execution or
submission, and post-processing). A task's work directory is under
`/home/cbrain/data/<bourreau name>/work` in the `bourreau` container.

Do not run specs with `exec web`: that container uses the development
database.

## Configuration

Set in the environment or in a `.env` file at the repository root:

| Variable | Default | Use |
|----------|---------|-----|
| `CBRAIN_PORTAL_PORT`  | `3000` | Port of the portal on the host |
| `CBRAIN_ADMINER_PORT` | `8080` | Port of Adminer (bound to 127.0.0.1) |
| `CBRAIN_UID`, `CBRAIN_GID` | `1000` | UID/GID of `cbrain` in the images; set them to yours (`id -u`, `id -g`) so files written in your checkout belong to you. Rebuild after a change |

## Starting over

To delete everything (database, files, caches, keys known to the portal) and
reinstall from step 3:

```bash
docker compose down -v
```

This removes all the volumes of the current setup's services. Your checkout
and the SSH key in `docker/ssh` are kept. If you used both setups, run it
with slurm selected, so the cluster's volumes are removed too.

## Troubleshooting

- **The portal exits at start**: `docker compose logs web`. A failed step of
  [What happens at each start](#what-happens-at-each-start) stops the start.
- **Tasks stay "New"**: the Bourreau or its task workers are not running;
  redo installation step 6.
- **The Bourreau does not start**: this must succeed without a password:
  `docker compose exec web ssh -i /home/cbrain/.ssh/id_cbrain_ed25519 cbrain@bourreau true`. If the Bourreau's host keys changed, see
  [ssh/README.md](ssh/README.md).
- **Warning about orphan containers**: the setup was switched without
  `docker compose down`. Run `docker compose up -d --remove-orphans`.
- **A task fails**: read its work directory (path in the task's log in the
  portal); Apptainer errors appear in `.science.err.*`. With slurm, see
  [slurm/README.md](slurm/README.md#troubleshooting).

## Limits

- One Bourreau at a time: two Bourreaux cannot run from the same checkout
  (they share `Bourreau/tmp` and `Bourreau/config/database.yml`). Switch
  setups instead.
- The container that runs Apptainer is privileged (`bourreau` with unix,
  `c1` with slurm). Many real HPCs run Apptainer without that.
- In production, only the portal runs in a container; Bourreaux run natively
  on the HPC login nodes.
