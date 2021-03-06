### -------- phageAnnote - Bacteriophage annotation pipeline using conda and snakemake -------- ###


# **** Imports ****
import os
import glob

# **** Variables ****

configfile: "config.yaml"
sequence_directory = config['fast_files']
miniconda_env = config['conda_env']
INTERPRO_BIN = config['interproscan']
BTSS_BIN = config['btssfinder']
EGGNOG = config['eggnog']
GFFREAD_BIN = config['gffread']
HMM_DB = config['hmmdb']
# VIRAL_PROTEINS = config['virus_refseq_protein'] # This can be added if using the --proteins option in prokka 
NUM_THREADS = 6


# **** Begin script ****

Samples, = glob_wildcards("raw_files/{sample}.fasta")


rule all:
    input:
        expand("results/{sample}_files/gff/{sample}.master.gff3", sample=Samples)


# **** Prokka annotation ****

rule prokka:
    input:
        "raw_files/{sample}.fasta"
    output:
        r1 = "results/{sample}.gbk",
        r2 = "results/{sample}.faa",
        r3 = "results/{sample}.fna"
    conda:
        "envs/prokka.yaml"
    params:
        sample_name = "{sample}"
    threads: NUM_THREADS
    priority:
        50
    shell:
        """
        echo Annotating...
        mkdir -p results
        mkdir -p results/edits
        prokka --kingdom Viruses --gcode 11 --prefix {params.sample_name} --locustag {params.sample_name} --addmrna --addgenes --notrna --outdir results {input} --force
        """

rule trnascan:
    input:
        "raw_files/{sample}.fasta"
    output:
        r1 = "results/{sample}_trnascan.txt",
        r2 = "results/{sample}_trnascan.bed",
        r3 = "results/{sample}_aragorn.txt"
    conda:
        "envs/prokka.yaml"
    params:
        sample_name = "{sample}"
    threads: NUM_THREADS
    shell:
        """
        tRNAscan-SE -B -I --max -o {output.r1} -b {output.r2} {input}
        aragorn -l -gc11 -w {input} -o {output.r3}
        """

#rule blastp:
#    input:
#        rules.prokka.output.r2
#    output:
#        "results/{sample}_blastp_alignment.tbl"
#    conda:
#        "envs/prokka.yaml"
#    params:
#        sample_name = "{sample}"
#    threads: NUM_THREADS
#    shell:
#        """
#        blastp -db /home/js/phageAnnote/viral_proteins/refseq_viral -query {input} -max_target_seqs 1 -outfmt '6 qaccver saccver stitle pident bitscore score' -out {output}
#        """

# **** Search for acquired AMR and virulence genes with Abricate****


rule abricate:
    input:
        r1 = "results/{sample}.gbk", # ensure we have a .gbk file to use for this rule
        r2 = rules.trnascan.output, # wait for tRNAscan to finish running before starting this rule
        r3 = rules.prokka.output # wait for prokka to finish running before starting this rule
    output:
        r1 = "results/{sample}_amr.tbl",
        r2 = "results/{sample}_amr_resfinder.tbl",
        r3 = "results/{sample}_amr_argannot.tbl",
        r4 = "results/{sample}_virulence.tbl",
        r5 = "results/{sample}_summary.tbl"
    conda:
        "envs/prokka.yaml"
    params:
        sample_name = "{sample}"
    threads: NUM_THREADS
    shell:
        """
        echo Annotating Virulence and AMR...
        abricate -db ncbi {input.r1} > {output.r1}
        abricate -db resfinder {input.r1} > {output.r2}
        abricate -db argannot {input.r1} > {output.r3}
        abricate -db vfdb {input.r1} > {output.r4}
        abricate --summary {output.r1} {output.r2} {output.r3} {output.r4} > {output.r5}
        """

# **** Predict AMR genes using NCBI _amrfinder

rule ncbi_amr:
    input:
        r1 = "results/{sample}.faa", # ensure we have a .faa file to use for this rule, generated by prokka typically
        r2 = rules.abricate.output # wait for abricate to finish running before starting this rule
    output:
        "results/{sample}_ncbi_amr.txt"
    conda:
        "envs/prokka.yaml"
    params:
        sample_name = "{sample}"
    threads: NUM_THREADS
    shell:
        """
        echo Annotating AMR using NCBI-AMRFINDERPLUS...
        amrfinder -u
        amrfinder -p {input.r1} --plus --threads {NUM_THREADS} -o {output}
        """

# **** Annotate prokaryotic virus orthologous group proteins from pVOG database using Hmmer

rule pvog:
    input:
        r1 = "results/{sample}.faa", # ensure we have a .faa file to use for this rule, generated by prokka typically
        r2 = rules.ncbi_amr.output  # wait for ncbi AMR to finish running before starting this rule
    output:
        r1 = "results/{sample}_alignment.tbl",
        r2 = "results/{sample}_alignment.align"
    conda:
        "envs/prokka.yaml"
    params:
        sample_name = "{sample}"
    threads: NUM_THREADS
    shell:
        """
        echo Begginning hmmsearch for {input} with pVOG
        hmmsearch --domtblout {output.r1} -A {output.r2} -o results/{params.sample_name}_vog.txt {HMM_DB} {input.r1}
        """

# **** GBK2PTT creates a coordinate file from a .GBK input generated by prokka for use with TransTermHP ****

rule gbk2ptt:
    input:
        r1 = "results/{sample}.gbk", # ensure we have a .gbk file to use for this rule, generated by prokka typically
        r2 = rules.prokka.output # wait for prokka to finish running before starting this rule
    output:
        "results/{sample}.ptt"
    conda:
        "envs/regulatory.yaml"
    threads: NUM_THREADS
    shell:
        """
        perl scripts/gbk2ptt.pl < {input.r1} > {output}
        """

# **** Predict Rho-independent terminators with TransTermHP ****

rule transterm:
    input:
        r1 = "results/{sample}.ptt", # ensure we have a .faa file to use for this rule, generated by gbk2ptt rule above
        r2 = rules.pvog.output # wait for pVOG rule to finish running before starting this rule
    output:
        r1 = "results/{sample}_tthp.bag",
        r2 = "results/{sample}_tthp.tt"
    conda:
        "envs/regulatory.yaml"
    threads: NUM_THREADS
    params:
        sample_name = "{sample}"
    shell:
        """
        echo Annotating Terminators...
        transterm -p scripts/expterm.dat results/{params.sample_name}.fna {input.r1} --bag-output {output.r1} > {output.r2}
        """

# **** Predict bacterial Sigma 70 promoters with bTSSfinder ****

rule btssfinder:
    input:
        r1 = "results/{sample}.gbk",  # ensure we have a .gbk file to use for this rule, generated by prokka typically
        r2 = rules.transterm.output  # wait for TranstermpHP rule to finish running before starting this rule
    output:
        "results/{sample}_btss.bed"
    conda:
        "envs/regulatory.yaml"
    threads: NUM_THREADS
    params:
        sample_name = "{sample}"
    shell:
        """
        echo Annotating promoters...
        python scripts/get_intergene.py {input.r1}
        mv {params.sample_name}_ign.fasta results
        export bTSSfinder_Data="{BTSS_BIN}/Data"
        {BTSS_BIN}/bTSSfinder -i results/{params.sample_name}.fna -o results/{params.sample_name}_btss -a 1.94 -c 70 -t e
        """

# Predict protein families and additional protein functions using INTERPROSCAN for the proteins predicted by prokka

rule interproscan:
    input:
        r1 = "results/{sample}.faa",  # ensure we have a .faa file to use for this rule, generated by prokka typically
        r2 = rules.btssfinder.output
    output:
        "results/{sample}.faa.gff3"
    conda:
        "envs/interproscan.yaml"
    threads: NUM_THREADS
    params:
        sample_name = "{sample}"
    shell:
        """
        echo Annotating protein functions...
        {INTERPRO_BIN}/interproscan.sh -i {input.r1} --appl TMHMM,pfam --iprlookup --goterms --pathways -d results
        """

# Run Eggnog-mapper after Interproscan has finished. Looks for protein homology via Eggnog-mapper.

rule eggnog:
    input:
        r1 = "results/{sample}.faa",  # ensure we have a .faa file to use for this rule, generated by prokka typically
        r2 = rules.interproscan.output
    output:
        "results/{sample}.emapper.annotations"
    conda:
        "envs/eggnog.yaml"
    threads: NUM_THREADS
    params:
        sample_name = "{sample}"
    priority:
        5
    shell:
        """
        python {EGGNOG} -i {input.r1} --output results/{params.sample_name} --cpu 6 -m diamond --override
        """

# **** Clean files for gff3 format. This produces a GFF3 file that can be viewed in Geneious or any other GFF3 file viewer. It does not contain all of the data acquired in the pipeline, only the barebones skeleton used in our lab.
# This rule could likely be replaced with a python or R script. The objective here is to take all the files produced by each previous rule and create a single GFF3 file that contains all relevant information. The code below essentially conducts text manipulation and editing to produce this file.

rule gff_format_short:
    input:
        rules.eggnog.output # Eggnog-mapper rule as above should be the last rule run before this rule is allowed to start. This is a simpler way of telling the rule to wait until all required files are produced, since each previous rule checks for that already
    output:
        "results/{sample}_files/gff_short/{sample}.master.gff3"
    conda:
        "envs/interproscan.yaml"
    threads: NUM_THREADS
    params:
        sample_name = "{sample}"
    shell:
        """
        mkdir -p results/edits
        
        
        echo Aligning Sequence Data for short annotation...

        {GFFREAD_BIN}/gffread results/{params.sample_name}.gff -g results/{params.sample_name}.faa --tlf > results/edits/{params.sample_name}.tlf
        sed -i 's,\({params.sample_name}\)\(.*ID=\)\(.*\)\(_mRNA.*\),\\3\\2\\3\\4,g' results/edits/{params.sample_name}.tlf
        cp results/{params.sample_name}.gff results/edits/{params.sample_name}_prokka.edit.gff


        echo Collecting InterProScan5 Data and formatting...

        sed '1,3d' results/{params.sample_name}.faa.gff3 | sed 's/##sequence.*//g' | sed '/##FASTA/,$d' | sed 's/protein_match/CDS/; s/date=[[:digit:]]\+\x2d[[:digit:]]\+\x2d[[:digit:]]\+;//; s/Target={params.sample_name}_[[:digit:]]\+[[:space:]][[:digit:]]\+[[:space:]][[:digit:]]\+//; s/ID=match\$[[:digit:]]\+\x5f[[:digit:]]\+\x5f[[:digit:]]\+//; s/status=T;//; s/;;/;/; s/polypeptide/CDS/g' | tr -s '\n' | sort -k 1,1 > results/edits/{params.sample_name}.faa.gff
        awk -v FS='\t' -v OFS='\t' 'NR==FNR{{a[$1]=$4;b[$1]=$5; next}}{{$4=a[$1]; $5=b[$1]; print}}' results/edits/{params.sample_name}.tlf results/edits/{params.sample_name}.faa.gff > results/edits/{params.sample_name}_interpro.edit.gff
        cat results/edits/{params.sample_name}_interpro.edit.gff | grep 'TMHMM' > results/edits/{params.sample_name}_interpro_tmhmm.edit.gff3 || true
        awk -v FS='\t' -v OFS='\t' 'NR==FNR{{$9=\x22;note=Region of a membrane-bound protein predicted to be embedded in the membrane as predicted by TMHMM version 2.0c\x3b\x22; print}}' results/edits/{params.sample_name}_interpro_tmhmm.edit.gff3 > results/edits/{params.sample_name}_interpro_tmhmm.edit.2.gff3 && mv results/edits/{params.sample_name}_interpro_tmhmm.edit.2.gff3 results/edits/{params.sample_name}_interpro_tmhmm.edit.gff3
        if [[ -s results/edits/{params.sample_name}_interpro_tmhmm.edit.gff3 ]]; then awk -v FS='\t' -v OFS='\t' 'NR==FNR{{a[$3$4]=$9; next}}{{$3$4 in a; $9 = $9a[$3$4]; print}}' results/edits/{params.sample_name}_interpro_tmhmm.edit.gff3 results/edits/{params.sample_name}_prokka.edit.gff >  results/edits/{params.sample_name}_prokka.interpro.edit.gff; else cp results/edits/{params.sample_name}_prokka.edit.gff results/edits/{params.sample_name}_prokka.tmhmm.edit.gff; fi


        echo Collecting pVOG Data and formatting...

        sed '1,3d' results/{params.sample_name}_alignment.tbl | head -n -11 | tr -s '\n' | awk -F" " -v OFS='\t' '{{print $1, "pVOG", "CDS", "4", "5", "6", "7", "8", ";note=pVOG family " $4 ";"}}' | sort -k 1,1 > results/edits/{params.sample_name}_alignment.tbl
        awk -v FS='\t' -v OFS='\t' 'NR==FNR{{a[$1]=$4;b[$1]=$5; next}}{{$4=a[$1]; $5=b[$1]; print}}' results/edits/{params.sample_name}.tlf results/edits/{params.sample_name}_alignment.tbl > results/edits/{params.sample_name}_alignment.edit.gff
        awk -v FS='\t' -v OFS='\t' 'NR==FNR{{a[$3$4]=$9; next}}{{$3$4 in a; $9 = $9a[$3$4]; print}}' results/edits/{params.sample_name}_alignment.edit.gff results/edits/{params.sample_name}_prokka.interpro.edit.gff > results/edits/{params.sample_name}_prokka.pvog.edit.gff

        echo Collecting AMR and Virulence Data and formatting...

        awk -v FS='\t' -v OFS='\t' '{{print $1, "NCBI", "CDS", "4", "5", "6", "7", "8",  ";note="$5" gene" " similar to " $15 ", " $3 " predicted by NCBI AMRFinder Plus;"}}' results/{params.sample_name}_ncbi_amr.txt > results/edits/{params.sample_name}_ncbi_amr.gff
        awk -v FS='\t' -v OFS='\t' '{{print $2, "ABRICATE","CDS", $3, $4, ".", $5, ".", ";note=Virulence factor similar to " $14 " predicated by Abricate v1.0.0;"}}' results/{params.sample_name}_virulence.tbl > results/edits/{params.sample_name}_virulence.gff
        awk -v FS='\t' -v OFS='\t' 'NR==FNR{{a[$1]=$4;b[$1]=$5; next}}{{$4=a[$1]; $5=b[$1]; print}}' results/edits/{params.sample_name}.tlf results/edits/{params.sample_name}_ncbi_amr.gff > results/edits/{params.sample_name}_ncbi_amr.edit.gff
        awk -v FS='\t' -v OFS='\t' 'NR==FNR{{a[$3$4]=$9; next}}{{$3$4 in a; $9 = $9a[$3$4]; print}}' results/edits/{params.sample_name}_ncbi_amr.edit.gff results/edits/{params.sample_name}_prokka.pvog.edit.gff > results/edits/{params.sample_name}_prokka.amr.edit.gff
        awk -v FS='\t' -v OFS='\t' 'NR==FNR{{a[$3$4]=$9; next}}{{$3$4 in a; $9 = $9a[$3$4]; print}}' results/edits/{params.sample_name}_virulence.gff results/edits/{params.sample_name}_prokka.amr.edit.gff > results/edits/{params.sample_name}_prokka.abricate.edit.gff


        echo Collecting Promoter Data and formatting...

        cp results/{params.sample_name}_btss.gff results/edits/{params.sample_name}_btss.gff
        sed -i '1,9d' results/edits/{params.sample_name}_btss.gff
        if [[ -s results/edits/{params.sample_name}_btss.gff ]]; then grep '+' results/edits/{params.sample_name}_btss.gff | awk -v FS='\t' -v OFS='\t' '{{print $1, $2, "promoter", $4-36, $5-6, $6, $7, $8, "note=sigma70 promoter predicted by bTSSfinder" $9}}' > results/edits/{params.sample_name}_btss.final.gff; else cp results/edits/{params.sample_name}_btss.gff results/edits/{params.sample_name}_btss.final.gff; fi
        if [[ -s results/edits/{params.sample_name}_btss.final.gff ]]; then sed 's/promoter=sigma70//; s/;box10pos=/ box10pos:/; s/;box35pos=/ box35pos:/; s/;box10seq=/ box10seq:/; s/;box35seq=/ box35seq:/g' results/edits/{params.sample_name}_btss.final.gff > results/edits/{params.sample_name}_btss.final2.gff; else cp results/edits/{params.sample_name}_btss.final.gff results/edits/{params.sample_name}_btss.final2.gff; fi
        if [[ -s results/edits/{params.sample_name}_btss.final2.gff ]]; then grep 'promoter' results/edits/{params.sample_name}_btss.final2.gff > results/edits/{params.sample_name}_btss.final.gff3; else cp results/edits/{params.sample_name}_btss.final2.gff results/edits/{params.sample_name}_btss.final.gff3; fi


        echo Collecting Terminator Data and formatting...

        sed 's/.*{params.sample_name}_[0-9]\{{5\}}/{params.sample_name}\tTranstermHP\tTerminator\t/; s/.*NONE.*//g' results/{params.sample_name}_tthp.bag > results/edits/{params.sample_name}_tthp.edit.bag
        tr -s '\n' < results/edits/{params.sample_name}_tthp.edit.bag > results/edits/{params.sample_name}_tthp.edit.gff
        sed -i 's,\({params.sample_name}\tTranstermHP\tTerminator\t\)[[:blank:]]\+\([[:digit:]]\+\)[[:blank:]]\+\x2e\x2e[[:blank:]]\+\([[:digit:]]\+\)[[:blank:]]\+\([\x2b\x2d]\)[[:blank:]]\+[\x2d\x2b].*[\x2d\x2b][[:digit:]]\+\x2e[[:digit:]]\+[[:blank:]]\+\([[:upper:]]\+\)[[:blank:]]\+\(.*[[:blank:]]\+.*[[:blank:]]\+.*\)[[:blank:]]\+\([[:upper:]]\+\)[[:blank:]]\+[[:digit:]]\+[[:blank:]]\+[[:digit:]]\+$,\\1\\2\t\\3\t\x2e\t\\4\t\x2e\tnote=Rho-Independent Terminator predicted by TranstermHP v2.08\x3b,g' results/edits/{params.sample_name}_tthp.edit.gff
        grep '{params.sample_name}' results/edits/{params.sample_name}_tthp.edit.gff > results/edits/{params.sample_name}_tthp.final.gff3

        echo Cleaning up empty tags from gff3 files that we don't need...

        sed 's/;inference=ab initio prediction:Prodigal:002006,similar to AA sequence:refseq_viral_proteins:\([YN].*\)\(;locus_tag=.*product=\)\(.*\)\s\(\[.*\]\)/\\2\\3;note=Similar to \\1 \\3 \\4/g' results/edits/{params.sample_name}_prokka.abricate.edit.gff > results/edits/{params.sample_name}_prokka.edit.gff
        sed -i 's/\t\x3b/\x3b/; s/inference=ab initio prediction:Prodigal:002006;//; s/.*\tmRNA\t.*//; s/signature_desc=/note=/; s/[[:alpha:]]\+=;//; s/note=Eggnog-mapper predicted functional annotation: ;//; s/db_xref=KEGG:;//; s/;;/;/g' results/edits/{params.sample_name}_prokka.edit.gff
        tr -s '\n' < results/edits/{params.sample_name}_prokka.edit.gff > results/edits/{params.sample_name}_prokka.edit.2.gff
        tr -s ';' < results/edits/{params.sample_name}_prokka.edit.2.gff > results/edits/{params.sample_name}_prokka.final.gff
        sed -i 's/product=hypothetical protein .*;note=Similar/product=hypothetical protein;note=Similar/; s/status=T;//; s/product=.* hypothetical protein;note=Similar/product=hypothetical protein;note=Similar/; s/putative//g' results/edits/{params.sample_name}_prokka.final.gff

        echo Moving files to final locations...

        mkdir -p finished_genomes
        mkdir -p results/{params.sample_name}_files
        mkdir -p results/{params.sample_name}_files/gff_short
        cp results/edits/{params.sample_name}_tthp.final.gff3 results/{params.sample_name}_files/gff_short
        cp results/edits/{params.sample_name}_btss.final.gff3 results/{params.sample_name}_files/gff_short
        cp results/edits/{params.sample_name}_prokka.final.gff results/{params.sample_name}_files/gff_short

        echo Generating GFF3 master file...
        cat results/{params.sample_name}_files/gff_short/{params.sample_name}*.gff3 results/{params.sample_name}_files/gff_short/{params.sample_name}_prokka.final.gff > results/{params.sample_name}_files/gff_short/{params.sample_name}.master.gff3
        echo Removing temporary files...
        rm results/edits/*

        echo Done!
        """
        
        
       # This rule creates a lengthened version of the final GFF3 file that is currently not used in our lab, but provides all the details acquired from each step in the annotation.
    # This rule could likely be replaced with a python or R script. The objective here is to take all the files produced by each previous rule and create a single GFF3 file that contains all relevant information. The code below essentially conducts text manipulation and editing to produce this file.
    
rule gff_format_all:
    input:
        rules.gff_format_short.output
    output:
        "results/{sample}_files/gff/{sample}.master.gff3"
    conda:
        "envs/interproscan.yaml"
    threads: NUM_THREADS
    params:
        sample_name = "{sample}"
    shell:
        """
        mkdir -p results/edits
        echo Aligning Sequence Data...

        {GFFREAD_BIN}/gffread results/{params.sample_name}.gff -g results/{params.sample_name}.faa --tlf > results/edits/{params.sample_name}.tlf
        sed -i 's,\({params.sample_name}\)\(.*ID=\)\(.*\)\(_mRNA.*\),\\3\\2\\3\\4,g' results/edits/{params.sample_name}.tlf
        cp results/{params.sample_name}.gff results/edits/{params.sample_name}_prokka.edit.gff


        echo Collecting InterProScan5 Data...

        sed '1,3d' results/{params.sample_name}.faa.gff3 | sed 's/##sequence.*//g' | sed '/##FASTA/,$d' | sed 's/protein_match/CDS/; s/date=[[:digit:]]\+\x2d[[:digit:]]\+\x2d[[:digit:]]\+;//; s/Target={params.sample_name}_[[:digit:]]\+[[:space:]][[:digit:]]\+[[:space:]][[:digit:]]\+//; s/ID=match\$[[:digit:]]\+\x5f[[:digit:]]\+\x5f[[:digit:]]\+//; s/status=T;//; s/;;/;/; s/polypeptide/CDS/g' | tr -s '\n' | sort -k 1,1 > results/edits/{params.sample_name}.faa.gff
        awk -v FS='\t' -v OFS='\t' 'NR==FNR{{a[$1]=$4;b[$1]=$5; next}}{{$4=a[$1]; $5=b[$1]; print}}' results/edits/{params.sample_name}.tlf results/edits/{params.sample_name}.faa.gff > results/edits/{params.sample_name}_interpro.edit.gff
        cat results/edits/{params.sample_name}_interpro.edit.gff | grep 'TMHMM' > results/edits/{params.sample_name}_interpro_tmhmm.edit.gff3 || true
        awk -v FS='\t' -v OFS='\t' 'NR==FNR{{$9=\x22;note=Region of a membrane-bound protein predicted to be embedded in the membrane as predicted by TMHMM version 2.0c\x3b\x22; print}}' results/edits/{params.sample_name}_interpro_tmhmm.edit.gff3 > results/edits/{params.sample_name}_interpro_tmhmm.edit.2.gff3 && mv results/edits/{params.sample_name}_interpro_tmhmm.edit.2.gff3 results/edits/{params.sample_name}_interpro_tmhmm.edit.gff3
        cat results/edits/{params.sample_name}_interpro.edit.gff | grep 'Pfam' > results/edits/{params.sample_name}_interpro_pfam.edit.gff3 || true
        sed -i 's/signature_desc=/;note=InterProScan5 signature description: /; s/Name=PF/;db_xref=PFAM:PF/g' results/edits/{params.sample_name}_interpro_pfam.edit.gff3
        if [[ -s results/edits/{params.sample_name}_interpro_tmhmm.edit.gff3 ]]; then awk -v FS='\t' -v OFS='\t' 'NR==FNR{{a[$3$4]=$9; next}}{{$3$4 in a; $9 = $9a[$3$4]; print}}' results/edits/{params.sample_name}_interpro_tmhmm.edit.gff3 results/edits/{params.sample_name}_prokka.edit.gff >  results/edits/{params.sample_name}_prokka.tmhmm.edit.gff; else cp results/edits/{params.sample_name}_prokka.edit.gff results/edits/{params.sample_name}_prokka.tmhmm.edit.gff; fi
        if [[ -s results/edits/{params.sample_name}_interpro_pfam.edit.gff3 ]]; then awk -v FS='\t' -v OFS='\t' 'NR==FNR{{a[$3$4]=$9; next}}{{$3$4 in a; $9 = $9a[$3$4]; print}}' results/edits/{params.sample_name}_interpro_pfam.edit.gff3 results/edits/{params.sample_name}_prokka.tmhmm.edit.gff >  results/edits/{params.sample_name}_prokka.interpro.edit.gff; else cp results/edits/{params.sample_name}_prokka.tmhmm.edit.gff results/edits/{params.sample_name}_prokka.interpro.edit.gff; fi
        sed -i 's/Ontology_term/db_xref/; s/Name=PF/db_xref=PFAM:PF/; s/Dbxref/db_xref/g' results/edits/{params.sample_name}_prokka.interpro.edit.gff


        echo Collecting pVOG Data...

        sed '1,3d' results/{params.sample_name}_alignment.tbl | head -n -11 | tr -s '\n' | awk -F" " -v OFS='\t' '{{print $1, "pVOG", "CDS", "4", "5", "6", "7", "8", ";note=pVOG family " $4 ";"}}' | sort -k 1,1 > results/edits/{params.sample_name}_alignment.tbl
        awk -v FS='\t' -v OFS='\t' 'NR==FNR{{a[$1]=$4;b[$1]=$5; next}}{{$4=a[$1]; $5=b[$1]; print}}' results/edits/{params.sample_name}.tlf results/edits/{params.sample_name}_alignment.tbl > results/edits/{params.sample_name}_alignment.edit.gff
        awk -v FS='\t' -v OFS='\t' 'NR==FNR{{a[$3$4]=$9; next}}{{$3$4 in a; $9 = $9a[$3$4]; print}}' results/edits/{params.sample_name}_alignment.edit.gff results/edits/{params.sample_name}_prokka.interpro.edit.gff > results/edits/{params.sample_name}_prokka.pvog.edit.gff


        echo Collecting AMR and Virulence Data...

        awk -v FS='\t' -v OFS='\t' '{{print $1, "NCBI", "CDS", "4", "5", "6", "7", "8",  ";note="$5" gene" " similar to " $15 ", " $3 " predicted by NCBI AMRFinder Plus;"}}' results/{params.sample_name}_ncbi_amr.txt > results/edits/{params.sample_name}_ncbi_amr.gff
        awk -v FS='\t' -v OFS='\t' '{{print $2, "ABRICATE","CDS", $3, $4, ".", $5, ".", ";note=Virulence factor similar to " $14 " predicated by Abricate v1.0.0;"}}' results/{params.sample_name}_virulence.tbl > results/edits/{params.sample_name}_virulence.gff
        awk -v FS='\t' -v OFS='\t' 'NR==FNR{{a[$1]=$4;b[$1]=$5; next}}{{$4=a[$1]; $5=b[$1]; print}}' results/edits/{params.sample_name}.tlf results/edits/{params.sample_name}_ncbi_amr.gff > results/edits/{params.sample_name}_ncbi_amr.edit.gff
        awk -v FS='\t' -v OFS='\t' 'NR==FNR{{a[$3$4]=$9; next}}{{$3$4 in a; $9 = $9a[$3$4]; print}}' results/edits/{params.sample_name}_ncbi_amr.edit.gff results/edits/{params.sample_name}_prokka.pvog.edit.gff > results/edits/{params.sample_name}_prokka.amr.edit.gff
        awk -v FS='\t' -v OFS='\t' 'NR==FNR{{a[$3$4]=$9; next}}{{$3$4 in a; $9 = $9a[$3$4]; print}}' results/edits/{params.sample_name}_virulence.gff results/edits/{params.sample_name}_prokka.amr.edit.gff > results/edits/{params.sample_name}_prokka.abricate.edit.gff

        echo Collecting promoter data...

        cp results/{params.sample_name}_btss.gff results/edits/{params.sample_name}_btss.gff
        sed -i '1,9d' results/edits/{params.sample_name}_btss.gff
        if [[ -s results/edits/{params.sample_name}_btss.gff ]]; then grep '+' results/edits/{params.sample_name}_btss.gff | awk -v FS='\t' -v OFS='\t' '{{print $1, $2, "promoter", $4-38, $5-6, $6, $7, $8, "note=sigma70 promoter predicted by bTSSfinder," $9}}' > results/edits/{params.sample_name}_btss.final.gff; else cp results/edits/{params.sample_name}_btss.gff results/edits/{params.sample_name}_btss.final.gff; fi
        if [[ -s results/edits/{params.sample_name}_btss.final.gff ]]; then sed 's/promoter=sigma70//; s/;box10pos=/ box10pos:/; s/;box35pos=/ box35pos:/; s/;box10seq=/ box10seq:/; s/;box35seq=/ box35seq:/g' results/edits/{params.sample_name}_btss.final.gff > results/edits/{params.sample_name}_btss.final2.gff; else cp results/edits/{params.sample_name}_btss.final.gff results/edits/{params.sample_name}_btss.final2.gff; fi
        if [[ -s results/edits/{params.sample_name}_btss.final2.gff ]]; then grep 'promoter' results/edits/{params.sample_name}_btss.final2.gff > results/edits/{params.sample_name}_btss.final.gff3; else cp results/edits/{params.sample_name}_btss.final2.gff results/edits/{params.sample_name}_btss.final.gff3; fi


        echo Collecting Terminator Data...

        sed 's/.*{params.sample_name}_[0-9]\{{5\}}/{params.sample_name}\tTranstermHP\tTerminator\t/; s/.*NONE.*//g' results/{params.sample_name}_tthp.bag > results/edits/{params.sample_name}_tthp.edit.bag
        tr -s '\n' < results/edits/{params.sample_name}_tthp.edit.bag > results/edits/{params.sample_name}_tthp.edit.gff
        sed -i 's,\({params.sample_name}\tTranstermHP\tTerminator\t\)[[:blank:]]\+\([[:digit:]]\+\)[[:blank:]]\+\x2e\x2e[[:blank:]]\+\([[:digit:]]\+\)[[:blank:]]\+\([\x2b\x2d]\)[[:blank:]]\+[\x2d\x2b].*[\x2d\x2b][[:digit:]]\+\x2e[[:digit:]]\+[[:blank:]]\+\([[:upper:]]\+\)[[:blank:]]\+\(.*[[:blank:]]\+.*[[:blank:]]\+.*\)[[:blank:]]\+\([[:upper:]]\+\)[[:blank:]]\+[[:digit:]]\+[[:blank:]]\+[[:digit:]]\+$,\\1\\2\t\\3\t\x2e\t\\4\t\x2e\tnote=Rho-Independent Terminator predicted by TranstermHP v2.08\x3b,g' results/edits/{params.sample_name}_tthp.edit.gff
        grep '{params.sample_name}' results/edits/{params.sample_name}_tthp.edit.gff > results/edits/{params.sample_name}_tthp.final.gff3

        echo Collecting Eggnog_mapper Data...

        sed '1,4d' results/{params.sample_name}.emapper.annotations | head -n -3 | awk -v FS='\t' -v OFS='\t' '{{print $1, "EGG", "CDS", "4", "5", "6", "7", "8", ";note=Eggnog-mapper predicted functional annotation: " $22 ";"}}' > results/edits/{params.sample_name}.emapper.annotations.edit
        awk -v FS='\t' -v OFS='\t' 'NR==FNR{{a[$1]=$4;b[$1]=$5; next}}{{$4=a[$1]; $5=b[$1]; print}}' results/edits/{params.sample_name}.tlf results/edits/{params.sample_name}.emapper.annotations.edit > results/edits/{params.sample_name}.emapper.annotations.edit.2
        awk -v FS='\t' -v OFS='\t' 'NR==FNR{{a[$3$4]=$9; next}}{{$3$4 in a; $9 = $9a[$3$4]; print}}' results/edits/{params.sample_name}.emapper.annotations.edit.2 results/edits/{params.sample_name}_prokka.abricate.edit.gff > results/edits/{params.sample_name}_prokka.eggnog.edit.gff

        echo Finding start codon...
        grep -A 1 '>{params.sample_name}_[[:digit:]]\+' results/{params.sample_name}.ffn | grep -o -e '>{params.sample_name}_[[:digit:]]\+' -e '^[[:alpha:]]..' | awk '{{print}}' ORS='''\t' | sed 's/\x3e/\\n/g' | awk -v FS='\t' -v OFS='\t' '{{print $1, "Start", "CDS", "4", "5", "6", "7", "8", ";note=Start codon: "$2 ";"}}' > results/{params.sample_name}_startcodon.gff
        awk -v FS='\t' -v OFS='\t' 'NR==FNR{{a[$1]=$4;b[$1]=$5; next}}{{$4=a[$1]; $5=b[$1]; print}}' results/edits/{params.sample_name}.tlf results/{params.sample_name}_startcodon.gff > results/edits/{params.sample_name}_startcodon.gff
        awk -v FS='\t' -v OFS='\t' 'NR==FNR{{a[$3$4]=$9; next}}{{$3$4 in a; $9 = $9a[$3$4]; print}}' results/edits/{params.sample_name}_startcodon.gff results/edits/{params.sample_name}_prokka.eggnog.edit.gff > results/edits/{params.sample_name}_prokka.codon.edit.gff

        echo Cleaning up empty tags...

        sed 's/;inference=ab initio prediction:Prodigal:002006,similar to AA sequence:refseq_viral_proteins:\([YN].*\)\(;locus_tag=.*product=\)\(.*\)\s\(\[.*\]\)/\\2\\3;note=Similar to \\1 \\3 \\4/g' results/edits/{params.sample_name}_prokka.codon.edit.gff > results/edits/{params.sample_name}_prokka.edit.gff
        sed -i 's/\t\x3b/\x3b/; s/inference=ab initio prediction:Prodigal:002006;//; s/.*\tmRNA\t.*//; s/signature_desc=/note=/; s/[[:alpha:]]\+=;//; s/note=Eggnog-mapper predicted functional annotation: ;//; s/db_xref=KEGG:;//; s/;;/;/g' results/edits/{params.sample_name}_prokka.edit.gff
        tr -s '\n' < results/edits/{params.sample_name}_prokka.edit.gff > results/edits/{params.sample_name}_prokka.edit.2.gff
        tr -s ';' < results/edits/{params.sample_name}_prokka.edit.2.gff > results/edits/{params.sample_name}_prokka.final.gff
        sed -i 's/product=hypothetical protein .*;note=Similar/product=hypothetical protein;note=Similar/; s/status=T;//; s/product=.* hypothetical protein;note=Similar/product=hypothetical protein;note=Similar/; s/putative//g' results/edits/{params.sample_name}_prokka.final.gff

        echo Moving files...

        mkdir -p finished_genomes
        mkdir -p results/{params.sample_name}_files
        mkdir -p results/{params.sample_name}_files/gff
        cp results/edits/{params.sample_name}_tthp.final.gff3 results/{params.sample_name}_files/gff
        cp results/edits/{params.sample_name}_btss.final.gff3 results/{params.sample_name}_files/gff
        cp results/edits/{params.sample_name}_prokka.final.gff results/{params.sample_name}_files/gff

        echo Generating GFF3 master file...
        cat results/{params.sample_name}_files/gff/{params.sample_name}*.gff3 results/{params.sample_name}_files/gff/{params.sample_name}_prokka.final.gff > results/{params.sample_name}_files/gff/{params.sample_name}.master.gff3
        mv results/*{params.sample_name}*.* results/{params.sample_name}_files
        mv raw_files/{params.sample_name}.fasta finished_genomes
        mkdir -p results/{params.sample_name}_files/finished_files
        cp results/{params.sample_name}_files/gff_short/{params.sample_name}.master.gff3 results/{params.sample_name}_files/finished_files
        cp results/{params.sample_name}_files/{params.sample_name}.faa results/{params.sample_name}_files/finished_files
        cp results/{params.sample_name}_files/{params.sample_name}_startcodon.gff results/{params.sample_name}_files/finished_files
        cp results/{params.sample_name}_files/{params.sample_name}_summary.tbl results/{params.sample_name}_files/finished_files
        cp results/{params.sample_name}_files/{params.sample_name}_ncbi_amr.txt results/{params.sample_name}_files/finished_files
        cp results/{params.sample_name}_files/{params.sample_name}_ign.fasta results/{params.sample_name}_files/finished_files
        cp results/{params.sample_name}_files/{params.sample_name}_trnascan.bed results/{params.sample_name}_files/finished_files

        echo Removing temporary files...
        rm results/edits/*
        echo Done!
        """
#        if [[ -s results/edits/{params.sample_name}_btss.gff ]]; then grep '-' results/edits/{params.sample_name}_btss.gff | awk -v FS='\t' -v OFS='\t' '{{print $1, $2, "promoter", $4+13, $5+38, $6, $7, $8, "note=sigma70 promoter predicted by bTSSfinder," $9}}' >> results/edits/{params.sample_name}_btss.final.gff; else echo next; fi

#        echo Finding start codon...
#        grep -A 1 '>{params.sample_name}_[[:digit:]]\+' results/{params.sample_name}.ffn | grep -o -e '>{params.sample_name}_[[:digit:]]\+' -e '^[[:alpha:]]..' | awk '{{print}}' ORS='''\t' | sed 's/\x3e/\\n/g' | awk -v FS='\t' -v OFS='\t' '{{print $1, "Start", "CDS", "4", "5", "6", "7", "8", ";note=Start codon: "$2 ";"}}' > results/{params.sample_name}_startcodon.gff
#        awk -v FS='\t' -v OFS='\t' 'NR==FNR{{a[$1]=$4;b[$1]=$5; next}}{{$4=a[$1]; $5=b[$1]; print}}' results/edits/{params.sample_name}.tlf results/{params.sample_name}_startcodon.gff > results/edits/{params.sample_name}_startcodon.gff
#        awk -v FS='\t' -v OFS='\t' 'NR==FNR{{a[$3$4]=$9; next}}{{$3$4 in a; $9 = $9a[$3$4]; print}}' results/edits/{params.sample_name}_startcodon.gff results/edits/{params.sample_name}_prokka.abricate.edit.gff > results/edits/{params.sample_name}_prokka.codon.edit.gff
#
#cat results/edits/{params.sample_name}_interpro.edit.gff | grep 'Coils' > results/edits/{params.sample_name}_interpro_coils.edit.gff3 || true
#sed -i 's/Name=Coil/note=Coiled-coil domain predicted in protein by InterProScan5/g' results/edits/{params.sample_name}_interpro_coils.edit.gff3

#        echo Collecting Eggnog_mapper Data...

#        sed '1,4d' results/{params.sample_name}.emapper.annotations | head -n -3 | awk -v FS='\t' -v OFS='\t' '{{print $1, "EGG", "CDS", "4", "5", "6", "7", "8", ";note=Eggnog-mapper predicted functional annotation: " $22 ";"}}' > results/edits/{params.sample_name}.emapper.annotations.edit
#        awk -v FS='\t' -v OFS='\t' 'NR==FNR{{a[$1]=$4;b[$1]=$5; next}}{{$4=a[$1]; $5=b[$1]; print}}' results/edits/{params.sample_name}.tlf results/edits/{params.sample_name}.emapper.annotations.edit > results/edits/{params.sample_name}.emapper.annotations.edit.2
#        awk -v FS='\t' -v OFS='\t' 'NR==FNR{{a[$3$4]=$9; next}}{{$3$4 in a; $9 = $9a[$3$4]; print}}' results/edits/{params.sample_name}.emapper.annotations.edit.2 results/edits/{params.sample_name}_prokka.pvog.edit.gff > results/edits/{params.sample_name}_prokka.eggnog.edit.gff
