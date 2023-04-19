# This file is a part of ParaReal. License is MIT: https://spdx.org/licenses/MIT.html

#!/bin/bash
#SBATCH -J report
#SBATCH -o out/startup-report_JOBID=%j.csv
#SBATCH -e %x-%j.err
#SBATCH --time=1:00
#SBATCH --partition=short
#SBATCH --mail-type=FAIL,END
#SBATCH --mail-user=jschulze@mpi-magdeburg.mpg.de

set -e

OUTDIR=out

# Annotate and concat individual benchmarks:
echo "JOBID, N, T, run, t_load, t_solve"
for jobid in $(cat startup.jobid);
do
  f=${OUTDIR}/startup_JOBID=${jobid}*.csv
  N=$(echo $f | sed -r 's/^.*_N=(.).*$/\1/')
  T=$(echo $f | sed -r 's/^.*_T=(.).*$/\1/')
  sed -e "s/^/$jobid, $N, $T, /" $f
done

# Create link to most recent report:
ln -sf ${OUTDIR}/startup-report_JOBID=${SLURM_JOBID}.csv startup-report.csv
