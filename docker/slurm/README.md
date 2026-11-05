# Emulated HPC cluster (Slurm)

A small Slurm cluster in `docker-compose.yml`, so that CBRAIN tasks run the
way they do on an HPC: the Bourreau submits a job with `sbatch`, the job runs
on a compute node that sees only the shared filesystem, and the tool's
software comes from a module or an Apptainer image, never from the Bourreau.
It is the **slurm** setup of the development environment: select it in
`docker-compose.yml` ([../README.md](../README.md#two-setups)), which then
merges `docker-compose.slurm.yml` over `docker-compose.unix.yml`.
Installation: [../README.md](../README.md).

```
portal (web) ──ssh──► bourreau = login node  (Bourreau Rails app, Slurm client, Apptainer)
                         │ sbatch / squeue / sacct
                         ▼
                      slurmctld ◄── slurmdbd ◄── slurmdb (MariaDB 11.4, accounting)
                         │
                         ▼
                         c1 = compute node   (slurmd, Lmod modules, Apptainer)

shared filesystem: volume bourreau_data, mounted at /home/cbrain/data
on bourreau and c1 (bourreau_slurm/work, bourreau_slurm/cache, dp)
```

## Files

| Path | Content |
|------|---------|
| `../../docker-compose.slurm.yml` | The cluster's services, and the changes to the unix setup: Bourreau name `bourreau_slurm`, cluster type SLURM, Slurm client config and munge key on the Bourreau, which is not privileged here |
| `Dockerfile` | One image (`cbrain-slurm`) for every role: Slurm 24.11, munge, Lmod, Apptainer, ffmpeg module. Same Debian release as the Bourreau, so the client and daemons match |
| `entrypoint.sh` | Starts munge, then the role given as argument: `slurmdbd`, `slurmctld` or `slurmd` |
| `etc/slurm.conf` | The cluster: node `c1` (2 CPUs, 2 GB), partition `cbrain` (default, 60 minutes maximum). Read by every node and by the Bourreau |
| `etc/slurmdbd.conf.in` | Accounting daemon settings (installed with mode 600 at start) |
| `etc/cgroup.conf` | Disables cgroups, which containers do not provide |
| `etc/task_prolog.sh` | Makes `module` available in the jobs' non-interactive bash |

The Bourreau's side is in `Bourreau/Dockerfile` (Slurm client, munge,
Apptainer) and `Bourreau/bin/docker-entrypoint` (starts munge). All Slurm
containers share one munge key, created on the first start in the
`munge_key` volume.

## How a task runs

1. The portal sends the task to the Bourreau `bourreau_slurm` (cluster type
   SLURM, driver `Bourreau/lib/scir_slurm.rb`).
2. Task setup, on the Bourreau: the work directory is created under
   `/home/cbrain/data/bourreau_slurm/work`, inputs are synced to the cache
   `/home/cbrain/data/bourreau_slurm/cache`, and for a containerized tool the
   image is built once (`apptainer build`) and cached as a CBRAIN file.
3. The Bourreau submits the job script with `sbatch`; it runs on `c1` as user
   `cbrain`, in the same work directory.
4. The job runs the ToolConfig's prologue (e.g. `module load ffmpeg`) and the
   tool's command, inside `apptainer exec` when the ToolConfig has an image.
5. The Bourreau follows the job with `squeue`, reads its CPU times with
   `sacct`, then saves the outputs to the Data Provider.

Follow it in `Bourreau/log/TaskWorkers.combined.log`, with `squeue` / `sacct`
on the login node, and in the task's work directory (`.qsub.*`, `.science.*`
and `.singularity.*` files).

## Providing a tool's software

The Bourreau has no science tools, as on a real cluster. Two ways:

### Apptainer image (recommended)

Give the descriptor a container image:

```json
"container-image": {
    "type":  "docker",
    "image": "jrottenberg/ffmpeg:8.0.3-ubuntu2404",
    "index": "docker://"
}
```

When the Bourreau boots and creates the tool's ToolConfig, it fills in the
container settings from it (engine Singularity, which means Apptainer here).
For an existing ToolConfig, set them in the portal: container engine
`Singularity`, index `docker://`, image name. The image must contain `bash`:
CBRAIN's wrapper script runs inside the container. The Bourreau needs
network access to pull it; `c1` does not, it uses the cached copy.

### Module

As on HPCs with Lmod: install the software under `/opt/apps/<tool>/<version>`
in `docker/slurm/Dockerfile`, add a modulefile under
`/opt/apps/modulefiles/<tool>/<version>.lua` (see the ffmpeg example in the
Dockerfile), rebuild (`docker compose build c1 && docker compose up -d c1`),
and set the ToolConfig's **script prologue** to `module load <tool>`.
To check on the node: `docker compose exec -u cbrain c1 bash -l`, then
`module avail`.

## Useful commands

```bash
docker compose exec -u cbrain bourreau sinfo        # partition and node state
docker compose exec -u cbrain bourreau squeue       # queued and running jobs
docker compose exec -u cbrain bourreau sacct -X     # finished jobs (accounting)
docker compose logs -f slurmctld c1                 # daemon logs
```

## Limits

- **Privileged compute node.** `c1` runs with `privileged: true` and
  Apptainer's setuid starter (the Bourreau, which only builds images, is not
  privileged in this setup). Unprivileged Apptainer needs user namespaces,
  which Docker's seccomp and AppArmor profiles block, and Ubuntu hosts with
  `kernel.apparmor_restrict_unprivileged_userns=1` block them even when the
  container is unconfined. Many real HPCs run Apptainer without setuid; this is
  the main difference from them. Never use this setting outside development.
- **Small and short.** One node, 2 CPUs, 2 GB, 60 minutes per job: for testing
  the loop and small inputs, not for real computations.
- **No cgroups.** Jobs are tracked with `proctrack/linuxproc`; memory and CPU
  limits are not enforced.
- **MariaDB 11.4 for accounting.** Slurm 24.11's SQL fails on MariaDB 13
  (`mariadb:latest`), hence the pinned version of `slurmdb`.

## Troubleshooting

- **Node `c1` is `down` or `drain`** in `sinfo`: `docker compose logs c1`, then
  `docker compose restart c1`.
- **`slurmctld` restarts in a loop with "CLUSTER ID MISMATCH"**: the
  accounting database and the controller state were reset separately. Reset
  both: `docker compose rm -sf slurmdb slurmdbd slurmctld`, then
  `docker volume rm cbrain_slurmdb_data cbrain_slurmctld_state`, then
  `docker compose up -d`.
- **A job fails**: read the task's work directory on the shared volume
  (`docker compose exec -u cbrain c1 ls -a /home/cbrain/data/bourreau_slurm/work/...`); the
  task's log in the portal gives the path. `module: command not found` means
  the job did not get the TaskProlog; Apptainer errors appear in
  `.science.err.*`.
