#!/bin/env bash
#$ -cwd
#$ -l h_rt=300:00:00
#$ -l mem_free=15G
#$ -t 1-100

module load CBI r plink bcftools miniforge3
conda activate py_ped_sim_clean

# Inputs: Superpopulation Label
while getopts s: flag
do
    case "${flag}" in
        s) super_pop=${OPTARG};;
    esac
done

# Input parameters
#input_dir=/wynton/scratch/guardado075/king_hap_ibd/large_fam_recomb_map
#vcf_output="${input_dir}/largefam_${super_pop}_seed${SGE_TASK_ID}_merged_genomes.vcf.gz"

input_dir=/wynton/scratch/guardado075/king_hap_ibd/large_fam_1000sims
vcf_output="${input_dir}/largefam_${super_pop}_seed${SGE_TASK_ID}_merged_genomes.vcf.gz"
bed_file="${input_dir}/largefam_${super_pop}_seed${SGE_TASK_ID}_merged_genomes"
output_prefix=~/rohlfs_lab/igg_prelim/king_hap_ibd/large_fam_1000sims/results/king_full/large_fam_${super_pop}_seed${SGE_TASK_ID}

#large_fam_${POP}_seed${SEED}_chr${CHR}_hapmap_re8

# First we need to combine individuals chromosome jobs
bcftools concat ${input_dir}/large_fam_${super_pop}_seed${SGE_TASK_ID}_chr{1..22}_hapmap_re8_genomes.vcf  -Oz -o $vcf_output
plink --vcf $vcf_output --make-bed --out "$bed_file"

# Next we run KING to estimate kinship coefficients for all pairs of individuals in the simulated data
~/bin/king -b ${bed_file}.bed --kinship --ibdseg --prefix "$output_prefix"