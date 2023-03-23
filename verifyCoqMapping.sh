#!/bin/bash
#
# USAGE: verify.sh model.pml property1 property2 ...
#   or   cat properties.txt | xargs verify.sh <bpmn_file> <property_file>

properties=(size_3_path_exists fair_size_3_path_exists has_required_actions phase_sequence_correct has_no_duplicate_receives_0a has_no_duplicate_receives_0b has_no_duplicate_receives_1 has_no_duplicate_receives_2 has_no_duplicate_receives_3 has_no_duplicate_receives_4 )
expectedResults=(1 1 0 0 0 0 0 0 0 0)
model="MatchCoqModel.pml"

for i in ${!properties[@]}
do
  prop=${properties[$i]}
  printf "${prop}:\t"
  if spin -run -ltl ${prop} -f -m50000 ${model} | grep -q "errors: 0"
  then
      printf "No Errors Found.\t"
      if [ ${expectedResults[i]} -eq 0 ]
      then
          printf "No Errors Expected\t\033[0;32mPASSED\033[0m\n"
      else 
          printf "Errors Expected  \t\033[0;31mFAILED\033[0m\n"
      fi
  else 
      printf "Errors Found.\t"
      if [ ${expectedResults[i]} -eq 1 ]
      then
          printf "Errors Expected  \t\033[0;32mPASSED\033[0m\n"
      else 
          printf "No Errors Expected\t\033[0;31mFAILED\033[0m\n"
      fi
  fi &
  wait $!
done
