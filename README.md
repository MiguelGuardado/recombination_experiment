# recombination_experiment

A controlled experiment testing how the **recombination model used during genome
simulation** affects the simulated data and the downstream relatedness estimates
computed on it. It is part of the large-family / forensic genetic-ancestry (IGG)
project and uses [`py_ped_sim`](https://github.com/MiguelGuardado/py_ped_sim) to
drop a fixed large-family pedigree onto 1000 Genomes reference haplotypes, then
`KING` to estimate kinship and IBD segments.

The experiment crosses two factors:

| | **re6** (rate ≈ `1e-6`) | **re8** (rate ≈ `1e-8`) |
|---|---|---|
| **Constant** recombination rate | `run_simulations_constant_re6.sh` | `run_simulations_constant_re8.sh` |
| **Map-based** (HapMap) recombination | `run_simulations_map_re6.sh` | `run_simulations_map_re8.sh` |

The four simulation scripts are identical except for how recombination is
specified, which is exactly the variable under study: the "constant" scripts pass
a single genome-wide rate to `py_ped_sim` (`-r 1e-6` or `-r 1e-8`), while the
"map" scripts pass a per-chromosome HapMap genetic map (`-rm
hapmap_re6_chr*.txt` or `hapmap_re8_chr*.txt`). Comparing the resulting kinship /
IBD estimates across the four cells shows how sensitive the inference is to the
recombination assumptions.

All of the `run_*.sh` scripts are **SGE array jobs** written for the Wynton HPC
cluster (`#$ -t` sets the task range, `#$ -l` requests runtime/memory,
`module load` / `conda activate` set up the environment). The simulator
(`run_ped_sim.py`) and `king` are installed under `~/bin`. Most paths are
specific to the author's Wynton scratch/group space and will need editing to run
elsewhere.

## Pipeline overview

```
run_simulations_constant_re6.sh  ┐
run_simulations_constant_re8.sh  │  1. simulate genomes per (population, seed, chromosome)
run_simulations_map_re6.sh       │     under each recombination setting
run_simulations_map_re8.sh       ┘
            │
            ▼
run_king.sh   # 2. merge the 22 per-chromosome VCFs and run KING (kinship + IBD segments)
```

Each simulation script is an array job (up to 11,000 tasks) that reads one line
of `input_data/job_id_100sims.txt`, parsing it into `JOB`, `POP` (population),
`SEED`, and `CHR` (chromosome). It then runs `py_ped_sim`'s `sim_genomes_exact`
task to simulate genomes for the large-family pedigree
(`input_data/large_family_012326.nx`) from the matching 1000 Genomes reference
VCF, at mutation rate `1e-7`, writing output to the shared `recomb_results`
scratch directory with a suffix marking the variant. As in the rest of the
project, each simulation is wrapped in a retry loop (up to `MAX_RETRIES=100`)
that re-attempts until the expected `*_genomes.vcf` appears, so transient cluster
failures don't drop a task.

## Scripts

### `run_simulations_constant_re6.sh` / `run_simulations_constant_re8.sh`

Simulate genomes using a **single constant recombination rate** across the whole
genome, passed to `py_ped_sim` via `-r` — `1e-6` for the `re6` variant and `1e-8`
for the `re8` variant. Output prefixes end in `_constant_re6` / `_constant_re8`.

### `run_simulations_map_re6.sh` / `run_simulations_map_re8.sh`

Simulate genomes using an **empirical HapMap recombination map** instead of a
constant rate, passed via `-rm` as a per-chromosome map file
(`hapmap_re6_chr${CHR}.txt` or `hapmap_re8_chr${CHR}.txt`). Output prefixes end
in `_hapmap_re6` / `_hapmap_re8`. These are otherwise identical to the constant
scripts.

### `run_king.sh`

Post-simulation relatedness step. Selected by `-s` (superpopulation) with
`SGE_TASK_ID` as the replicate seed. It uses `bcftools concat` to merge the 22
per-chromosome simulated VCFs into one VCF, converts it to PLINK binary format
with `plink --make-bed`, and then runs **KING** (`king -b … --kinship --ibdseg`)
to estimate kinship coefficients and IBD segments for all pairs of individuals.

> **Heads up:** this `run_king.sh` was carried over from the `large_fam_1000sims`
> project and still points at that project's paths (`input_dir=…/large_fam_1000sims`,
> output under `…/large_fam_1000sims/results/king_full/`) and hard-codes the
> `_hapmap_re8_` filename suffix in the `bcftools concat` step. To run KING on a
> given recombination variant, update the input/output directories and the
> per-chromosome filename suffix (`_constant_re6`, `_constant_re8`, `_hapmap_re6`,
> or `_hapmap_re8`) to match the simulation you want to summarize.

## Inputs

Key files under `input_data/`:

- `job_id_100sims.txt` — task table (`JOB POP SEED CHR` per line) driving the simulation arrays.
- `large_family_012326.nx` — the large-family pedigree structure simulated by `py_ped_sim`.
- `large_family_012326.ped` / `large_family_012326_rel.csv` — the pedigree in PED form and its pairwise-relationship table (truth set for evaluating estimates).
- `genetic_map_hg38_withX.txt` — hg38 genetic map (used by downstream map-based steps).

## A note on data files

Large reference and result files (the genetic map, simulated VCFs, and KING
result files) are **not tracked in this repository** because they exceed
GitHub's file-size limits. They are regenerated by running the pipeline above,
or are available on the lab's Wynton storage.
