# phageAnnote

The objective of this project is to automate annotation of assembled bacteriophage genomes via a bioinformatic pipeline, standardizing phage genome annotation and reducing user time while providing valuable information pertaining to the phages potential use as a biocontrol. 

First, proteins, CDS and tRNA prediction is handled by Prokka, annotating against the prokka-supplied viral database. Next, an hmmprofile of pVOGs (http://dmk-brain.ecn.uiowa.edu/pVOGs/tutorial.html) is searched against the predicted coding regions identified by prokka with HMMER3. For promoter and terminator prediction, bTSSfinder provides prediction of sigma70 promoters, and TransTermHP predicts rho-independent terminators. InterProScan provides annotation of homologous proteins using popular databases such as pfam, TIGRFAM, and ProSitePatterns/Profiles, as well as prediction of protein transmembrane regions with Phobius and TMHMM. AMR and virulence genes are predicted by Abricate. Finally, all the produced files are editted to produce a single GFF3 file that contains all relevant information in one file.

annotation.snake is our snakemake file used to execute each rule in a specific order based on the input variables contained within each rule.
For each rule, think of the input variables as the required files that must be present before the rule is allowed to execute. The output variables are some of the files that are generated by the code that is executed by the rule. Not all files need to be specified, solely the ones you want to ensure are present.

The configuration.yaml file contains locations of folders, installation locations, etc. and needs to be updated for your workstation.

smaple.master.gff3 is a sample of the resulting gff3 file produced at the end of the pipeline. This file is the reviewed in Geneious and can be exported from there. 

## Installation

PhageAnnote was designed and tested on Ubuntu 18.04

1. Download and install InterProScan https://www.ebi.ac.uk/interpro/download/
2. Download and install bTSSfinder https://www.cbrc.kaust.edu.sa/btssfinder/about.php
3. Download and install TMHMM https://services.healthtech.dtu.dk/software.php
4. Download and install Eggnog-mapper https://github.com/eggnogdb/eggnog-mapper
5. Install conda (miniconda for example)
6. Download phageAnnote repository into local directory
7. Add raw sequence files to folder location specified in config.yaml
8. bTSSfinder and other programs may need to be added to your $HOME path to work within conda.

The config.yaml file should be updated to reflect your directory system and locations of specified programs.

## Running pipeline

Execute: snakemake --use-conda
