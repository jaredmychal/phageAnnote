# phageAnnote

The objective of this project is to automate annotation of assembled bacteriophage genomes via a bioinformatic pipeline, standardizing phage genome annotation and reducing user time while providing valuable information pertaining to the phages potential use as a biocontrol. CDS and tRNA prediction is handled by Prokka annotating against a custom protein database. An hmmprofile of pVOGs is searched against the predicted coding regions with HMMER3. bTSSfinder provides prediction of sigma70 promoters, and TransTermHP predicts rho-independent terminators. InterProScan provides annotation of pfam, TIGRFAM, and ProSitePatterns/Profiles, as well as prediction of protein transmembrane regions with Phobius and TMHMM. AMR and virulence genes are predicted by Abricate.

annotation.snake is our snakemake file
The configuration.yaml file contains locations of folders, installation locations, etc. and needs to be updated for your workstation.

smaple.master.gff3 is a sample of the resulting gff3 file produced at the end of the pipeline. This file is the reviewed in Geneious and can be exported from there. 

## Installation

1. Download and install InterProScan https://www.ebi.ac.uk/interpro/download/
2. Download and install bTSSfinder https://www.cbrc.kaust.edu.sa/btssfinder/about.php
3. Download and install TMHMM https://services.healthtech.dtu.dk/software.php
4. Download and install Eggnog-mapper https://github.com/eggnogdb/eggnog-mapper
5. Download phageAnnote repository into local directory
6. Add raw sequence files to folder location specified in config.yaml
7. Download all available viral refseq protein files and add to specified location in config.yaml

The config.yaml file should be updated to reflect your directory system.

## Running pipeline

Execute: snakemake --use-conda
