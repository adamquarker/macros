#!/usr/bin/bash

############################################
# Blair Seidlitz
# this script does an iterative emcal calib
# which runs event skimming on condor and 
# does fitting locally.
#
# iteration 0 -> iter=0
# pulls a calibration from currenttly calling it 
# local_calib_copy.root to use in calotowercalib 
# iteration 1
# tower slope method
# iteration >= 2 
# pi0 iterative method
#############################################


export TargetDir="$PWD"/condorout

iter=0

if [ "$iter" -eq 0 ]; then
  root "../Fun4All_EMCal.C(0,\"inputdata.txt\",0,\"local_calib_copy.root\")"
  iter=$((iter+1))
fi

# upper bound on x determines number of iterations
for((x=0;x<1;x++));
do

if [ -d ${TargetDir} ]; then
  if [ -d ${TargetDir}/OutDir0 ]; then
    rm -rf ${TargetDir}/OutDir*
  fi
else
  mkdir ${TargetDir}
fi
condor_rm bseidlitz

i=0
while read dir; do 
  li=$(printf "%04d" $i)

  rm inputdata.txt
  
  # creates a list of all files for a particular run
  for file in /sphenix/lustre01/sphnxpro/commissioning/DST_ana.387_2023p003/DST_CALOR-000"$dir"-*.root
  do
cat >>inputdata.txt<< EOF
$file
EOF
done

  if [ "$iter" -eq 1 ]; then
    j=8
  else
    j=100
  fi
  tot_files=$( cat inputdata.txt | wc -l )
  echo "total files: $tot_files"
  rem=$(( $tot_files%$j ))
  files_per_job=$(( $tot_files/$j ))
  njob=$j
  if [ $rem -ne 0 ]; then
    files_per_job=$(( $files_per_job+1 ))
  fi
  rem2=$(( $tot_files%$files_per_job ))
  njob=$(( $tot_files/$files_per_job ))
  if [ $rem2 -ne 0 ]; then
    njob=$(( ($tot_files/$files_per_job)+1 ))
  fi
  echo "files per job: $files_per_job"
  echo "njob: $njob"


  for((q=0;q<$njob;q++));
  do

    mkdir ${TargetDir}/OutDir$i
    export WorkDir="${TargetDir}/OutDir$i"
    echo "WorkDir:" ${WorkDir}
    start_file=$(( $q*$files_per_job+1 ))
    end_file=$(( $start_file+$files_per_job-1 ))
    echo "start file: $start_file   end file: $end_file"

    sed -n $start_file\,${end_file}p inputdata.txt > tmp.txt
    mv tmp.txt ${WorkDir}/inputdata.txt
    
    pushd ${WorkDir}

      
    
    cp -v "$PWD"/../../CondorRun.sh CondorRunJob$li.sh
    cp -v "$PWD"/../../local_calib_copy.root . 
    cp "$PWD"/../../../Fun4All_EMCal.C .

    sed -i "s/iteration/$iter/g" CondorRunJob$li.sh

    chmod +x CondorRunJob$li.sh
        
    
    cat >>ff.sub<< EOF
+JobFlavour                   = "workday"
transfer_input_files          = ${WorkDir}/CondorRunJob$li.sh, ${WorkDir}/inputdata.txt,${WorkDir}/Fun4All_EMCal.C
Executable                    = CondorRunJob$li.sh
request_memory                = 10GB
Universe                      = vanilla
Notification                  = Never
GetEnv                        = True
Priority                      = +12
Output                        = condor.out
Error                         = condor.err
Log                           = /tmp/condor$li.log
Notify_user                   = bs3402@columbia.edu

Queue
EOF

    condor_submit ff.sub
    popd
  
    i=$((i+1))
  done
done < runList.txt # redirect the input of the

# Set the directory where the files are located
file_directory="${TargetDir}/OutDir*/DONE.root"

while [ $(ls $file_directory | wc -l) -lt $((i-1)) ]; do
     current_file_count=$(ls $file_directory | wc -l)
    echo "Waiting for $((i-1)) files, currently $current_file_count"
    sleep 30  # Adjust the sleep duration as needed
done

export TargetHadd="$PWD"/combine_out

if [ ! -d ${TargetHadd} ]; then
  mkdir ${TargetHadd}
fi

file_to_hadd="${TargetDir}/OutDir*/OUTHIST_iter*.root"

hist_out=${TargetHadd}/out${iter}.root

rm $hist_out 

hadd -k $hist_out $file_to_hadd 

################################
# FITTING (not done with condor

if [ "$iter" -eq 1 ]; then
  root "../doTscFit.C(\"${hist_out}\",\"local_calib_copy.root\")"
else
  root "../doFitAndCalibUpdate.C(\"${hist_out}\",\"local_calib_copy.root\",$iter)"
fi

iter=$((iter+1))

done
