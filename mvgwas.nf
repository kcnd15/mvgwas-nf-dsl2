/*
 * Copyright (c) 2021, Diego Garrido-Martín
 *
 * This file is part of 'mvgwas-nf':
 * A Nextflow pipeline for multivariate GWAS using MANTA
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program. If not, see <http://www.gnu.org/licenses/>.
 */


// Define parameters

params.pheno = null
params.geno = null
params.cov = null
params.l = 500
params.t = 'none'
params.i = 'none'
params.ng = 10
params.dir = 'result'
params.out = 'mvgwas.tsv'
params.help = false


// Print usage

if (params.help) {
    log.info ''
    log.info 'mvgwas-nf: A pipeline for multivariate Genome-Wide Association Studies'
    log.info '=============================================================================================='
    log.info 'Performs multi-trait GWAS using using MANTA (https://github.com/dgarrimar/manta)'
    log.info ''
    log.info 'Usage: '
    log.info '    nextflow run mvgwas.nf [options]'
    log.info ''
    log.info 'Parameters:'
    log.info ' --pheno PHENOTYPES          phenotype file'
    log.info ' --geno GENOTYPES            indexed genotype VCF file'
    log.info ' --cov COVARIATES            covariate file'
    log.info " --l VARIANTS/CHUNK          variants tested per chunk (default: $params.l)"
    log.info " --t TRANSFOMATION           phenotype transformation: none, sqrt, log (default: $params.t)"
    log.info " --i INTERACTION             test for interaction with a covariate: none, <covariate> (default: $params.i)"
    log.info " --ng INDIVIDUALS/GENOTYPE   minimum number of individuals per genotype group (default: $params.ng)"
    log.info " --dir DIRECTORY             output directory (default: $params.dir)"
    log.info " --out OUTPUT                output file (default: $params.out)"
    log.info ''
    exit(1)
}


// Check mandatory parameters

if (!params.pheno) {
    exit 1, "Phenotype file not specified."
} else if (!params.geno) {
    params.help
    exit 1, "Genotype not specified."
} else if (!params.cov) {
    exit 1, "Covariate file not specified."
}


// Print parameter selection

log.info ''
log.info 'Parameters'
log.info '------------------'
log.info "Phenotype data               : ${params.pheno}"
log.info "Genotype data                : ${params.geno}"
log.info "Covariates                   : ${params.cov}"
log.info "Variants/chunk               : ${params.l}"
log.info "Phenotype transformation     : ${params.t}"
log.info "Interaction                  : ${params.i}"
log.info "Individuals/genotype         : ${params.ng}" 
log.info "Output directory             : ${params.dir}"
log.info "Output file                  : ${params.out}"
log.info ''


workflow {
  // sstats_ch.collectFile(name: "${params.out}", sort: { it.name }).set{pub_ch}
  filePheno = Channel.fromPath(params.pheno)
  fileCov = Channel.fromPath(params.cov)
  fileGenoVcf = Channel.fromPath(params.geno)
  fileGenoTbi = Channel.fromPath("${params.geno}.tbi")
  
  // fileIndex = Channel.fromPath("${params.geno}.tbi")
  
  // tuple_files = preprocess(filePheno, fileCov, fileVcf)
  // chunks = split(fileVcf, fileIndex)
  // mvgwas(tuple_files, fileVcf, fileIndex, chunks)
  
  // preprocess | flatten | split
  tuple_files = preprocess(filePheno, fileCov, fileGenoVcf)
  chunks = split(fileGenoVcf, fileGenoTbi) | flatten
  mvgwas(tuple_files, fileGenoVcf, fileGenoTbi, chunks)
}

// Split VCF
process split {
  
  debug true 
  
  input:
  file(vcf) // from file(params.geno)
  file(index) // from file("${params.geno}.tbi")
  
  output:
  path("chunk*")
  
  script:

  log.info "vcf-file: ${vcf}"  // e.g. eg.genotypes.vcf.gz
  log.info "tbi-file: ${index}"
  log.info "params.l: ${params.l}" // e.g. 500
  
  """
  echo "splitting file" $vcf $index
  bcftools query -f '%CHROM\t%POS\n' $vcf > positions
  split -d -a 10 -l ${params.l} positions chunk
  """
}

process split_original {
 
    input:

    file(vcf) // from file(params.geno)
    file(index) // from file("${params.geno}.tbi")    

    output:
    
    // file("chunk*") // into chunks_ch
    path("chunk*")

    script:
    log.info "vcf-file: ${vcf}"  // e.g. eg.genotypes.vcf.gz
    log.info "params.l: ${params.l}" // e.g. 500
    """
    bcftools query -f '%CHROM\t%POS\n' $vcf > positions
    split -d -a 10 -l ${params.l} positions chunk
    """
}


// Pre-process phenotypes and covariates

process preprocess {
  
    debug true
    
    input:
    path pheno_file
    path cov_file
    path vcf_file
    
    output:
    tuple file("pheno_preproc.tsv.gz"), file("cov_preproc.tsv.gz")
    
    script:
    """
    echo "preprocessing files" $pheno_file $cov_file $vcf_file
    echo "preprocess.R --phenotypes $pheno_file --covariates $cov_file --genotypes $vcf_file --out_pheno pheno_preproc.tsv.gz --out_cov cov_preproc.tsv.gz --verbose"
    preprocess.R --phenotypes $pheno_file --covariates $cov_file --genotypes $vcf_file --out_pheno pheno_preproc.tsv.gz --out_cov cov_preproc.tsv.gz --verbose
    """
}

process preprocess_2 {
    debug true 

    input:

    // file(pheno) from file(params.pheno)
    // file(cov) from file(params.cov)
    // file(vcf) from file(params.geno)
  
    path params.pheno
    // path cov_file
    // path vcf_file

    output:

    tuple file("pheno_preproc.tsv.gz"), file("cov_preproc.tsv.gz") // into preproc_ch
    
    script:
    """
    echo "Pheno file is: " $pheno_file
    echo "preprocess.R --phenotypes $pheno_file --covariates $cov_file --genotypes $vcf_file --out_pheno pheno_preproc.tsv.gz --out_cov cov_preproc.tsv.gz --verbose"
    preprocess.R --phenotypes $pheno_file --covariates $cov_file --genotypes $vcf_file --out_pheno pheno_preproc.tsv.gz --out_cov cov_preproc.tsv.gz --verbose
    """
}

process preprocess_original {
    debug true 

    input:

    // file(pheno) from file(params.pheno)
    // file(cov) from file(params.cov)
    // file(vcf) from file(params.geno)
    path pheno_file
    path cov_file
    path vcf_file

    output:

    tuple file("pheno_preproc.tsv.gz"), file("cov_preproc.tsv.gz") // into preproc_ch
    
    script:
    """
    echo "Pheno file is: " $pheno_file
    echo "preprocess.R --phenotypes $pheno_file --covariates $cov_file --genotypes $vcf_file --out_pheno pheno_preproc.tsv.gz --out_cov cov_preproc.tsv.gz --verbose"
    preprocess.R --phenotypes $pheno_file --covariates $cov_file --genotypes $vcf_file --out_pheno pheno_preproc.tsv.gz --out_cov cov_preproc.tsv.gz --verbose
    """
}


// GWAS: testing (MANTA)

process mvgwas {
    debug true 

    input:

    tuple file(pheno), file(cov) // from preproc_ch
    file(vcf) // from file(params.geno)
    file(index) // from file("${params.geno}.tbi")
    each path(chunk) // file(chunk) // from chunks_ch

    output:

    file('sstats.*.txt') optional true // into sstats_ch
    
    script:
    log.info "logging processing of file ${chunk}"
    
    """
    echo "processing file " $chunk
    
    chunknb=\$(basename $chunk | sed 's/chunk//')

    echo "chunknb:" \$chunknb
    
    # kc: change -ge 2 to -ge 1
    if [[ \$(cut -f1 $chunk | sort | uniq -c | wc -l) -ge 2 ]]; then
        echo "entering if..."
        k=1
        cut -f1 $chunk | sort | uniq | while read chr; do
        region=\$(paste <(grep -P "^\$chr\t" $chunk | head -n 1) <(grep -P "^\$chr\t" $chunk | tail -n 1 | cut -f2) | sed 's/\t/:/' | sed 's/\t/-/')
        
        echo "if region: [" \$region "]"
        echo "--output" sstats.\$k.tmp
        echo "test.R --phenotypes $pheno --covariates $cov --genotypes $vcf --region "\$region" --output sstats.\$k.tmp --min_nb_ind_geno ${params.ng} -t ${params.t} -i ${params.i} --verbose"
        
        test.R --phenotypes $pheno --covariates $cov --genotypes $vcf --region "\$region" --output sstats.\$k.tmp --min_nb_ind_geno ${params.ng} -t ${params.t} -i ${params.i} --verbose 
        
        ((k++))
    done
    # cat sstats.*.tmp > sstats.\${chunknb}.txt
    else
        echo "entering else..."
        
        region=\$(paste <(head -n 1 $chunk) <(tail -n 1 $chunk | cut -f2) | sed 's/\t/:/' | sed 's/\t/-/')
        
        echo "else region: [" \$region "]"
        echo "--output" sstats.\${chunknb}.txt
        echo "test.R --phenotypes $pheno --covariates $cov --genotypes $vcf --region "\$region" --output sstats.\${chunknb}.txt --min_nb_ind_geno ${params.ng} -t ${params.t} -i ${params.i} --verbose"
        
        test.R --phenotypes $pheno --covariates $cov --genotypes $vcf --region "\$region" --output sstats.\${chunknb}.txt --min_nb_ind_geno ${params.ng} -t ${params.t} -i ${params.i} --verbose
    fi
    """
}

process mvgwas_original {
    debug true 

    input:

    tuple file(pheno), file(cov) // from preproc_ch
    file(vcf) // from file(params.geno)
    file(index) // from file("${params.geno}.tbi")
    each path(chunk) // file(chunk) // from chunks_ch

    output:

    file('sstats.*.txt') optional true // into sstats_ch

    script:
    log.info "*** process mvgwas"
    log.info "chunk: ${chunk}"
    log.info "--phenotypes, pheno: ${pheno}"
    
    // chunknb=\$(basename -a $chunk | sed 's/chunk//')
    """
    chunknb=\$(basename $chunk | sed 's/chunk//')

    echo "chunknb:" \$chunknb >> ~/tmp.txt
    echo "--covariates" $cov >> ~/tmp.txt
    echo "--genotypes" $vcf >> ~/tmp.txt

    # kc: change -ge 2 to -ge 1
    if [[ \$(cut -f1 $chunk | sort | uniq -c | wc -l) -ge 1 ]]; then
        echo "entering if..." >> ~/tmp.txt
        k=1
        cut -f1 $chunk | sort | uniq | while read chr; do
        region=\$(paste <(grep -P "^\$chr\t" $chunk | head -n 1) <(grep -P "^\$chr\t" $chunk | tail -n 1 | cut -f2) | sed 's/\t/:/' | sed 's/\t/-/')
        echo "if region: [" \$region "]"n>> ~/tmp.txt
        echo "--output" sstats.\$k.tmp >> ~/tmp.txt
        echo "test.R --phenotypes $pheno --covariates $cov --genotypes $vcf --region "\$region" --output sstats.\$k.tmp --min_nb_ind_geno ${params.ng} -t ${params.t} -i ${params.i} --verbose" >> ~/tmp.txt
        test.R --phenotypes $pheno --covariates $cov --genotypes $vcf --region "\$region" --output sstats.\$k.tmp --min_nb_ind_geno ${params.ng} -t ${params.t} -i ${params.i} --verbose 
        ((k++))
    done
    # cat sstats.*.tmp > sstats.\${chunknb}.txt
    else
        echo "entering else..." >> ~/tmp.txt
        region=\$(paste <(head -n 1 $chunk) <(tail -n 1 $chunk | cut -f2) | sed 's/\t/:/' | sed 's/\t/-/')
        echo "else region: [" \$region "]" >> ~/tmp.txt
        echo "--output" sstats.\${chunknb}.txt >> ~/tmp.txt
        echo "test.R --phenotypes $pheno --covariates $cov --genotypes $vcf --region "\$region" --output sstats.\${chunknb}.txt --min_nb_ind_geno ${params.ng} -t ${params.t} -i ${params.i} --verbose" >> ~/tmp.txt
        test.R --phenotypes $pheno --covariates $cov --genotypes $vcf --region "\$region" --output sstats.\${chunknb}.txt --min_nb_ind_geno ${params.ng} -t ${params.t} -i ${params.i} --verbose
    fi
    """
}

// old: sstats_ch.collectFile(name: "${params.out}", sort: { it.name }).set{pub_ch}

// Summary stats

process end {

    publishDir "${params.dir}", mode: 'copy'     

    input:
    file(out) from pub_ch

    output:
    file(out) into end_ch

    script:
    if (params.i == 'none')
    """
    sed -i "1 s/^/CHR\tPOS\tID\tREF\tALT\tF\tR2\tP\\n/" ${out}
    """
    else
    """
    sed -i "1 s/^/CHR\tPOS\tID\tREF\tALT\tF($params.i)\tF(GT)\tF(${params.i}:GT)\tR2($params.i)\tR2(GT)\tR2(${params.i}:GT)\tP($params.i)\tP(GT)\tP(${params.i}:GT)\\n/" ${out}
    """
}
