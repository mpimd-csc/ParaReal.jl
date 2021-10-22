#!/bin/bash
#SBATCH -J bench
#SBATCH -o %x-%j.out
#SBATCH -e %x-%j.err
#SBATCH -n 4
#SBATCH -c 4
#SBATCH --time=1:00:00
#SBATCH --partition=short
#SBATCH --mail-type=FAIL,BEGIN,END
#SBATCH --mail-user=jschulze@mpi-magdeburg.mpg.de

set -e

export OMP_NUM_THREADS=${SLURM_CPUS_PER_TASK:-1}
export MKL_ENABLE_INSTRUCTIONS=AVX2
export JULIA_PROJECT=@.

module load apps/julia/1.6

julia startup-double.jl
