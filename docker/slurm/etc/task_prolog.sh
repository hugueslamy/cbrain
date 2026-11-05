#!/bin/sh

# Slurm TaskProlog, run on the compute node before each job step.
# Lines 'export NAME=value' printed here are added to the job's environment.
#
# CBRAIN runs the science script with a non-interactive bash, which reads
# no profile, so the 'module' command would not exist. BASH_ENV makes every
# such bash load Lmod first, as HPC environments usually arrange.

echo "export MODULEPATH=/opt/apps/modulefiles"
echo "export BASH_ENV=/usr/share/lmod/lmod/init/bash"
