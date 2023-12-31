# This file is a part of ParaReal. License is MIT: https://spdx.org/licenses/MIT.html

#!/bin/bash
#SBATCH -J bench
#SBATCH -o %x-%j.out
#SBATCH -e %x-%j.err
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=4
#SBATCH --time=15:00
#SBATCH --partition=short
#SBATCH --mail-type=FAIL,END
#SBATCH --mail-user=jschulze@mpi-magdeburg.mpg.de

set -e

export OMP_NUM_THREADS=${SLURM_CPUS_PER_TASK:-1}
export MKL_ENABLE_INSTRUCTIONS=AVX2
export JULIA_PROJECT=@.

module load apps/julia/1.6

julia startup-double.jl
