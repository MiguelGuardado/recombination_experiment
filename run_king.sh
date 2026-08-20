#!/bin/env bash
#$ -cwd
#$ -l h_rt=300:00:00
#$ -l mem_free=15G
#$ -t 1-100

# ------------------------------------------------------------------------------
# run_king.sh
#
# For one seed (SGE_TASK_ID) and one superpopulation (-s, default: afr), merge
# the 22 per-chromosome simulated VCFs for EACH of the four recombination
# variants and run KING separately on each merged VCF.
#
# Produces, per seed:
#   4 merged VCFs  (one per variant)
#   4 KING result sets (kinship + IBD segments), one per variant.
# ------------------------------------------------------------------------------

module load CBI r plink bcftools miniforge3
conda activate py_ped_sim_clean

# ---- Inputs -------------------------------------------------------------------
# Superpopulation label (afr / amr / eas / eur / sas). Defaults to afr.
super_pop=afr
while getopts s: flag; do
    case "${flag}" in
        s) super_pop=${OPTARG};;
    esac
done

# Seed = array task id (falls back to 1 for interactive testing)
seed="${SGE_TASK_ID:-1}"

# The four recombination variants (must match the simulation output suffixes).
variants=(constant_re6 constant_re8 hapmap_re6 hapmap_re8)

# ---- Paths --------------------------------------------------------------------
# Directory the simulation scripts write their per-chromosome VCFs to.
sim_dir=/wynton/scratch/guardado075/king_hap_ibd/recomb_results

# Where to write the merged VCFs / PLINK bed files (scratch).
merged_dir=${sim_dir}/merged
mkdir -p "$merged_dir"

# Where to write KING results (in-repo results dir).
results_dir=~/rohlfs_lab/igg_prelim/king_hap_ibd/recomb_experiment/results/king_full
mkdir -p "$results_dir"

echo "================================================================================"
echo "super_pop=${super_pop}  seed=${seed}  variants=${variants[*]}"
echo "sim_dir=${sim_dir}"
echo "================================================================================"

# ---- Per-variant loop ---------------------------------------------------------
for variant in "${variants[@]}"; do
    echo "--------------------------------------------------------------------------------"
    echo "[$(date +'%F %T')] VARIANT=${variant}  (seed=${seed}, pop=${super_pop})"

    base="large_fam_${super_pop}_seed${seed}_${variant}"
    vcf_output="${merged_dir}/${base}_merged_genomes.vcf.gz"
    bed_file="${merged_dir}/${base}_merged_genomes"
    output_prefix="${results_dir}/${base}"

    # Sanity check: make sure all 22 per-chromosome VCFs for this variant exist.
    missing=0
    for c in $(seq 1 22); do
        f="${sim_dir}/large_fam_${super_pop}_seed${seed}_chr${c}_${variant}_genomes.vcf"
        [[ -s "$f" ]] || { echo "  MISSING: $f"; missing=$((missing+1)); }
    done
    if [[ $missing -gt 0 ]]; then
        echo "  Skipping ${variant}: ${missing} per-chromosome VCF(s) missing."
        continue
    fi

    # 1. Combine the 22 per-chromosome VCFs into one merged VCF for this variant.
    bcftools concat \
        ${sim_dir}/large_fam_${super_pop}_seed${seed}_chr{1..22}_${variant}_genomes.vcf \
        -Oz -o "$vcf_output" \
        || { echo "  bcftools concat FAILED for ${variant}"; continue; }

    # 2. Convert the merged VCF to PLINK binary format.
    plink --vcf "$vcf_output" --make-bed --out "$bed_file" \
        || { echo "  plink --make-bed FAILED for ${variant}"; continue; }

    # 3. Run KING (kinship coefficients + IBD segments) on the merged genotypes.
    ~/bin/king -b "${bed_file}.bed" --kinship --ibdseg --prefix "$output_prefix" \
        || { echo "  KING FAILED for ${variant}"; continue; }

    echo "  [$(date +'%F %T')] DONE ${variant} -> ${output_prefix}*"
done

echo "================================================================================"
echo "[$(date +'%F %T')] All variants processed for seed=${seed}, pop=${super_pop}."

# End-of-job summary (if running as a job)
[[ -n "$JOB_ID" ]] && qstat -j "$JOB_ID"
