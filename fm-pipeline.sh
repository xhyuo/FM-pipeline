# 1-11-2017 MRC-Epid JHZ

# -/+ flanking position
export flanking=25000
# GWAS summary statistics (the .sumstats file)
export input=$1
# filename containing list of lead SNPs
export snplist=2.snps
# working directory
export wd=/genetics/data/gwas/6-7-17/MAGIC
# number of threads
export threads=5
# software to be included in the analysis; change flags to 1 when available
# the outputs should be available individually from them
export GCTA=0
export fgwas=0
export CAVIAR=1
export CAVIARBF=1
export finemap=1
export JAM=1

if [ $# -lt 1 ] || [ "$1" == "-h" ]; then
    echo "Usage: fm-pipeline.sh <input>"
    echo "where <input> is in sumstats format:"
    echo "SNP A1 A2 beta se N"
    echo "where SNP is RSid, A1 is effect allele"
    echo "and the outputs will be in <input>.out directory"
    exit
fi

if $(test -f snp150.txt ); then
   echo "Chromosomal positions are ready to use"
else
   echo "Obtaining chromosomal positions"
   wget http://hgdownload.soe.ucsc.edu/goldenPath/hg19/database/snp150Common.txt.gz
   gunzip -c snp150Common.txt.gz | cut -f2,4,5 | sort -k3,3 > snp150.txt
fi

# .sumstats with chromosomal positions
export input.input=$(basename ${input}).input
awk '{
  $2=toupper($2)
  $3=toupper($3)
}' $(input) | join -11 -23 - snp150.txt | sed 's/chr//g' > ${input.input)
head ${input.input}
sort -k1,1 ${snplist} | join ${input.input} - > $(basename ${snplist}).lst
wc -l $(basename ${snplist}).lst
grep -w -f ${snplist} ${input.input} | awk -vs=$f{lanking} '{print $8,$9-s,$9+s}' > st.bed

cat $(basename ${input.input}).lst | parallel -j${threads} -C' ' \
'awk "(\$8==chr && \$9 >= pos-s && \$9 <= pos+s){\$2=toupper(\$2);\$3=toupper(\$3); \
 if(\$2<\$3) {a1=\$2; a2=\$3;} else {a1=\$3; a2=\$2}; \
 \$0=\$0 \" \" \$8 \":\" \$9 \"_\" a1 \"_\" a2;print}" chr={8} pos={9} s=250000 MAGIC.txt | sort -k10,10 > {1}.dat'

cd MAGIC
ln -sf /gen_omics/data/EPIC-Norfolk/HRC/EPIC-Norfolk.sample
ln -sf $wd/rs2877716.dat chr3_122844451_123344451.dat
ln -sf $wd/rs17361324.dat chr3_122881254_123381254.dat
# --> map/ped
ls chr*.gen|sed 's/\.gen//g'|parallel -j${threads} --env wd -C' ' 'awk -f $wd/order.awk {}.gen > {}.ord;\
          gtool -G --g {}.ord --s EPIC-Norfolk.sample \
         --ped {}.ped --map {}.map --missing 0.05 --threshold 0.9 --log {}.log --snp --alleles \
         --chr $(echo {}|cut -d"_" -f1|sed "s/chr//g")'
# --> auxiliary files
ls *.info|sed 's/\.info//g'|parallel -j${threads} -C' ' 'sort -k2,2 {}.map|join -110 -22 {}.dat -|sort -k10,10>{}.incl'
cat $wd/st.bed | parallel -j${threads} --env wd -C' ' 'f=chr{1}_{2}_{3};\
     awk "{print \$9,\$10,\$5,\$6,\$7,\$8,15234,\$11,\$1,\$6/\$7}" $f.incl > $f.r2;\
     cut -d" " -f9,10 $f.r2>$f.z;\
     awk "{print \$1}" $f.incl > $f.inc;\
     awk "{print \$1,\$4,\$3,\$14,\$15}" $f.incl > $f.a;\
     echo "RSID position chromosome A_allele B_allele" > $f.incl_variants;\
     awk "{print \$1,\$10,\$9,\$4,\$3}" $f.incl >> $f.incl_variants'
# --> bfile
rm *bed *bim *fam
ls chr*.info|awk '(gsub(/\.info/,""))'|parallel -j${threads} --env wd -C' ' '\
         plink-1.9 --file {} --missing-genotype N --extract {}.inc --remove $wd/exclude.dat \
         --make-bed --keep-allele-order --a2-allele {}.a 3 1 --out {}'
# --> bcor
ls *.info|sed 's/\.info//g'|parallel -j${threads} -C' ' '\
         ldstore --bcor {}.bcor --bplink {} --n-threads ${threads}; \  
         ldstore --bcor {}.bcor --merge ${threads}; \
         ldstore --bcor {}.bcor --matrix {}.ld --incl_variants {}.incl_variants; \
         sed -i -e "s/  */ /g; s/^ *//; /^$/d" {}.ld'
# JAM, IPD
ls chr*.info|awk '(gsub(/\.info/,""))'|parallel -j${threads} -C' ' '\
         plink-1.9 --bfile {} --indep-pairwise 500kb 5 0.80 --maf 0.05 --out {}; \
         grep -w -f {}.prune.in {}.a > {}.p; \
         grep -w -f {}.prune.in {}.dat > {}p.dat; \
         plink-1.9 --bfile {} --extract {}.prune.in --keep-allele-order --a2-allele {}.p 3 1 --make-bed --out {}p'
ls *.info|sed 's/\.info//g'|parallel -j${threads} -C' ' '\ 
         grep -w -f {}.prune.in {}.z > {}p.z; \
         ldstore --bcor {}p.bcor --bplink {}p --n-threads ${threads}; \
         ldstore --bcor {}p.bcor --merge ${threads}; \
         ldstore --bcor {}p.bcor --matrix {}p.ld; \
         sed -i -e "s/  */ /g; s/^ *//; /^$/d" {}p.ld'
# --> finemap
echo "z;ld;snp;config;log;n-ind" > finemap.cfg
cat $wd/st.bed | parallel -j${threads} -C ' ' 'f=chr{1}_{2}_{3};sort -k7,7n $f.r2|tail -n1|cut -d" " -f7|\
awk -vf=$f "{print sprintf(\"%s.z;%s.ld;%s.snp;%s.config;%s.log;%d\",f,f,f,f,f,int(\$1))}" >> finemap.cfg'
finemap --sss --in-files finemap.cfg --n-causal-max 1 --corr-config 0.9
sed 's/\./p\./g' finemap.cfg > finemapp.cfg
finemap --sss --in-files finemapp.cfg --n-causal-max 1 --corr-config 0.9
# --> JAM
cat $wd/st.bed|parallel -j${threads} --env wd -C' ' 'export fp=chr{1}_{2}_{3}p; R CMD BATCH --no-save $wd/JAM.R ${fp}.log'

finemap --sss --in-files finemap.cfg --n-causal-max 3 --corr-config 0.9  
finemap --sss --in-files finemapp.cfg --n-causal-max 3 --corr-config 0.9