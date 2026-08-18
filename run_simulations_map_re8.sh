#!/bin/env bash
#$ -cwd
#$ -l h_rt=300:00:00
#$ -l mem_free=8G
#$ -t 1-11000

module load CBI r plink bcftools miniforge3
conda activate py_ped_sim_clean

# Based on the SGE_TASK_ID (or first arg), read the corresponding line from the input file and export variables
N=${1:-${SGE_TASK_ID:-1}}
FILE=${2:-input_data/job_id_100sims.txt}

line=$(sed -n "${N}p" "$FILE")
if [[ -z "$line" ]]; then
  echo "No line $N in $FILE" >&2
  exit 1
fi

read -r JOB POP SEED CHR <<< "$line"

export JOB POP SEED CHR

echo "JOB=$JOB POP=$POP SEED=$SEED CHR=$CHR"

# Set up paths and parameters for the simulation
vcf_filepath="/wynton/scratch/guardado075/ref_one_kg/onekg_${POP}_high_coverage_chr${CHR}_slim_fil.vcf.gz"
fasta_file="/wynton/group/hernandez/guardado075/hapibd/hg38_fasta/chrom_files/chr${CHR}.fa"
recomb_map="/wynton/group/hernandez/guardado075/founder_1kg/recomb_map/hapmap_re8_chr${CHR}.txt"
output_prefix="/wynton/scratch/guardado075/king_hap_ibd/recomb_results/large_fam_${POP}_seed${SEED}_chr${CHR}_hapmap_re8"

# ensure output directory exists
outdir=$(dirname "$output_prefix")
mkdir -p "$outdir"

expected_vcf="${output_prefix}_genomes.vcf"

# If MAX_RETRIES is set (>0) we'll stop after that many attempts; if 0 or unset, retry indefinitely
MAX_RETRIES=100

attempt=1
success=0

echo "RUNNING SIMULATION: JOB=$JOB (pop=$POP seed=$SEED chr=$CHR) - max retries: ${MAX_RETRIES:-unlimited}"
echo "Input VCF: $vcf_filepath"
echo "Output prefix: $output_prefix"


while true; do
  echo "--------------------------------------------------------------------------------"

  # run simulation (do not let script exit on non-zero)
  python ~/bin/py_ped_sim/run_ped_sim.py \
    -t sim_genomes_exact \
    -v "$vcf_filepath" \
    -f "$fasta_file" \
    -n input_data/large_family_012326.nx \
    -rm $recomb_map \
    -s "$SEED" \
    -mu 1e-7 \
    -o "$output_prefix" || true

  sim_elapsed=$(( SECONDS - sim_start ))

  if [[ -s "$expected_vcf" ]]; then
    echo "$(date +'%F %T') - SUCCESS (attempt $attempt) : $expected_vcf - took ${sim_elapsed}s"
    success=1
    break
  fi

  echo "$(date +'%F %T') - No output produced (expected: $expected_vcf). Cleaning and retrying..."
  rm -f "$expected_vcf" 2>/dev/null

  # check retry limit
  if [[ "$MAX_RETRIES" -gt 0 && "$attempt" -ge "$MAX_RETRIES" ]]; then
    echo "$(date +'%F %T') - FAILED: reached MAX_RETRIES=$MAX_RETRIES for JOB=$JOB seed=$SEED chr=$CHR"
    break
  fi

  ((attempt++))
  sleep 5
done

if [[ $success -ne 1 ]]; then
  echo "$(date +'%F %T') - Giving up on JOB=$JOB (pop=$POP seed=$SEED chr=$CHR)"
fi

# End-of-job summary (if running as a job)
[[ -n "$JOB_ID" ]] && qstat -j "$JOB_ID"