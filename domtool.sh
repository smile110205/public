# DOM_tool.sh 
# Maintained by: Rob Thomas / Bradley Mott
# Revision 1.7.5
# Last Modified 10/22/2016
# Please reference internal Knowledge Base articles relating to the use of this tool
# http://ikb.vmware.com/kb/2138954
#############################################
# -a   or   --all                 Execute 'DOM_tool.sh -pi' against all DOM objects. Saves to file 'cluster_objects.txt'
# -ab  or   --abdicate            Issues owner abdication request against a specified DOM object.
# -c   or   --csv                 Prints to CSV. Provides minimal object data (Faster). Outputs to 'objects.csv'
# -ci  or   --csvinfo             Similar to '-c'   Provides verbose object data (Slower). Outputs to 'objects.csv'
# -cs  or   --checkstate          Determine object health across the cluster
# -d   or   --disks               Print all Disk Utilization Statistics
# -h   or   --help                Display help menu
# -p   or   --pretty              Pretty-print all DOM/LSOM correlations. May also specify UUID: DOM_tool.sh -p <uuid>
# -pi  or   --prettyinfo          Similar to -p   Provides filename/filepath and type (objtool).
# -r   or   --resyncinfo          Prints all DOM objects that have bytes to resync
# -v   or   --vminfo              Gather objects for a specific Virtual Machine: DOM_tool.sh -v <Path To VMX File>
# -w   or   --whatif              Assess object health across the cluster in the event of a host/disk-group/disk failure.

####### Variables #######
# $0 is defined as script location/name
# $DOMobj used to call DOM object through loop and output LSOM information
# $workingdir is the working directory (by default /tmp/) 
workingdir="/tmp"
# #info determinds if objects should be looked up, or not, when using pretty-print
info="0"
# Version Check (legacy check for 5.5 to enable features like Disk Group identification in CSV files)
esxiversion="`vmware -v |sed 's/VMware ESXi //g' |awk -F\. '{print $1}'`"
#Version Testing (Leave next Line commented unless version-testing
#esxiversion="5"

####### Functions    #######
#FUNCTION to print Help
# Help function finds all options for operators based on "#HELP" beginning of line.
# please see examples contained in DO WORK section for more information
help() {
echo "Script to gather information on all DOM objects in a VSAN cluster"
echo "and determine information about underlying LSOM and hardware components"
echo "usage: DOM_tool.sh <operators>"
echo
echo Command line operators:
# Pull operators from this file
cat "$0" |grep ^#HELP |awk -F\, '{print "\t"$2"  or  "$3"\t\t"$4}' |sort -k1
}

#FUNCTION to check for 6,000+ objects, and redirect from /tmp
# this is meant to avoid running out of inodes in /tmp if too many objects in a big VSAN cluster
# default is /tmp unless redirected above in Variables.
sizecheck(){
# This function checks for greater than 10,000 DOM objects, and rather than exhaust /tmp of inodes, offers a redirect option
#LINE FOR DEBUG
#if [ `echo 15000` -gt "10000" ]
#PRODUCTION LINE
if [ `cmmds-tool find -f json -t DOM_OBJECT |grep uuid|wc -l` -gt "6000" ]
  then
  echo "Large VSAN cluster identified, it is recommended that you select a location other than the default for this output"
  echo "NOTE: This must be placed in a folder, and cannot be directed to the VSAN datastore's root directory (Vmware KB# 2119776)"
  echo -en "Please enter an alternate location for output (ex: "/vmfs/volumes/datstore1/data"): "
# Pull in user provided item and evaluate it
    read rawworkingdir
      if [ "$rawworkingdir" = "/tmp" ] || [ "$rawworkingdir" = "/tmp/" ] || [ "$rawworkingdir" = "../" ] || [ "$rawworkingdir" = "./" ] || [ "$rawworkingdir" = "." ]
        then
        echo "Unable to use relative paths. Please select a location other than /tmp and re-run. DOM_tool.sh will now exit."
        exit
      fi
# Remove trailing "/" if provided in path, as it is not expected later in the script
    workingdir="`echo $rawworkingdir |sed 's/\/$//g'`"
# Validate set working directory actually exists
      if [ ! -d "$workingdir" ]
        then
        echo "Directory does not exist, please double-check and run this script again."
        exit
      fi
fi
}
                                            

foldercheck() {
#FUNCTION to determine if outfiles already exist in /$workingdir/DOMobjs/
#If so, clear them and prep for run
## Folder Check ##
# If folder doesn't exist, create it
if [ ! -d "$workingdir/DOMobjs" ]
  then
      mkdir "$workingdir/DOMobjs"
# If $workingdir/DOMobjs already exists
  else
# Clean out prior runs, remove DOM objects
      rm -f "$workingdir/DOMobjs/"*
fi
}



gather_DOM() {
#FUNCTION to collect all DOM objects to /$workingdir/DOMobjs/
#### Data Gather (From CMMDS) ####
#Gather all DOM Objects
# Collect output from CMMDS for all DOM_OBJECT items, parse out only the DOM UUID's, and begin a loop
    cmmds-tool find -f json -t DOM_OBJECT |grep -F '   "uuid":' |awk -F\" '{print $4}' |while read DOMobj
      do
# Print all DOM object UUID's to files, with CMMDS data for each inside file
        cmmds-tool find -f json -t DOM_OBJECT -u $DOMobj >> "$workingdir/DOMobjs/$DOMobj"
      done
}

gather_DOM_single () {
#FUNCTION to collect single DOM objects to /$workingdir/DOMobjs/
#### Data Gather (From CMMDS) ####
#Gather all DOM Objects
# Collect output from CMMDS for all DOM_OBJECT items, parse out only the DOM UUID's, and begin a loop
    cmmds-tool find -f json -t DOM_OBJECT -u "$userin" |grep -F '   "uuid":' |awk -F\" '{print $4}' |while read DOMobj
      do
# Print all DOM object UUID's to files, with CMMDS data for each inside file
        cmmds-tool find -f json -t DOM_OBJECT -u $DOMobj > "$workingdir/DOMobjs/$DOMobj"
      done
}
                        

gather_HOSTS() {      
# Gather Hosts
# Pull all HOSTNAME entries from CMMDS, do some formatting to remove oddities, and begin a loop
cmmds-tool find -f json -t HOSTNAME |sed 's/\}//g;s/{//g;s/"//g;s/content: //g;s/,//g;' |grep -E "uuid:|hostname" |sed -e 's/^[ \t]*//' -e 's/[ \t]*$//' |sed 's/uuid: //g;s/hostname: //g'|sed 'N;s/\n/,/g'  |while read hosts
  do
# Pull UUID from CMMDS output
    uuid=`echo $hosts |awk -F\, '{print $1}'`
# Pull hostname entry from CMMDS output
    hostn=`echo $hosts |awk -F\, '{print $2}'`
# place hostname in file in /$workingdir/DOMobjs, with host_ prefix
    echo "$hostn" > "$workingdir/DOMobjs/host_$uuid"
  done
}

gather_DISKS() {
# Gather Disks            
# Find all disk objects in CMMDS, parse out UUID's, and begin a loop
cmmds-tool find -f json -t DISK |grep uuid |awk -F\" '{print $4}' |while read line
  do 
# Pull all disk information per DISK UUID into a file (including health status, etc)
    cmmds-tool find -f json -u $line > "$workingdir/DOMobjs/disk_$line"
  done
}

#FUNCTION to create all DOM Object pretty-print
prettyprint(){
# list all DOM objects, exlcude anything in the directory containing "host" or "disk", as these are not DOM objects, and begin a loop
ls "$workingdir/DOMobjs/" |grep -vE "host|disk|exclude" |while read line
  do 
# Print the object name
     echo "DOM Object: $line"
# Print LSOM components and format as appropriate
# sed is used heavily here for formatting reasons, to pull out extraneous characters used for JSON formatting. 
# unnecessary wording is pulled using sed find/replace: 's/find/replace/g', sometimes this is done more than once in a string 's/find/replace/g;s/find2/replace2/g'
     echo "LSOM Components:"
     cat "$workingdir/DOMobjs/$line" |grep content |sed 's/,/\n/g' |grep -E "componentUuid|componentState|faultDomain|diskUuid|type" |grep -v StateTS |sed 's/\}//g;s/{//g;s/"//g;s/content: //g;s/,//g;' |sed 's/attributes: //g' |grep -vE "Configuration|RAID" |sed 's/Witness/Witness  /g' |sed 'N;N;N;N;s/\n/ /g'
     echo "---------------------------------------------------------------------------------------------------------------------------------------------------------------------"
     echo ""
# Print it all to /$workingdir/objects.txt
  done > "$workingdir/objects.txt"
}


prettyprint_csv(){
# Determine if info flag is turned on
if [ "$info" = "1" ]
  then
   echo "DOM UUID,Exists?,File Path,DOM in File,Child Number,Component Type,State,FaultDomain,LSOM Component ID,Physical Disk ID,Physical Disk Owner,Disk Group UUID,," > "$workingdir/objects.csv"
# list all DOM objects, exlcude anything in the directory containing "host" or "disk", as these are not DOM objects, and begin a loop
    ls "$workingdir/DOMobjs/" |grep -vE "host|disk|exclude" |while read line
      do
# Print LSOM components and format as appropriate
# sed is used heavily here for formatting reasons, to pull out extraneous characters used for JSON formatting.
# unnecessary wording is pulled using sed find/replace: 's/find/replace/g', sometimes this is done more than once in a string 's/find/replace/g;s/find2/replace2/g'
        cat "$workingdir/DOMobjs/$line" |grep content |sed 's/,/\n/g' |grep -E "componentUuid|componentState|faultDomain|diskUuid|type" |grep -v StateTS |sed 's/\}//g;s/{//g;s/"//g;s/content: //g;s/,//g;' |sed 's/attributes: //g' |grep -vE "Configuration|RAID" |sed 's/Witness/Witness  /g' |sed 'N;N;N;N;s/\n/,/g' |sed "s/^/$line,/g" |sed 's/ type: /,/g;s/ child/child/g;s/ componentState: //g;s/ faultDomainId: //g;s/ componentUuid: //g;s/ diskUuid: //g'
# Print it all to /$workingdir/objects.csv
      done >> "$workingdir/objects.csv" 


## Check if file exists on VSAN
# Get a list of all DOM objects in csv file
  cat "$workingdir/objects.csv" |grep -v "DOM UUID"|awk -F\, '{print $1}' |sort |uniq |while read doms
    do
# Temporarily capture objtool output for parsing
      /usr/lib/vmware/osfs/bin/objtool getAttr -u $doms > "$workingdir/objinfo.temp"
       
# Determine whether the object is a namespace, or other, and evaluate it with an if-exist
      if [[ "`cat "$workingdir/objinfo.temp" |grep "Object class" |awk -F\: '{print $2}'`" = " vmnamespace" ]]
        then
# Define "friendly" variable to print out name of namespace "folder"
          friendly="`cat "$workingdir/objinfo.temp" |grep friendly |awk -F\: '{print $2}'`"
# Gather path to object (will simply be vsan root for namespace)
          vsanpath="`cat "$workingdir/objinfo.temp" |grep "Object path" |sed 's/Object path: //g'`"
          fullpath="`echo "$vsanpath$friendly"`"
          if [ -d "$fullpath" ]
            then
# use sed to find/replace the DOM object from "DOM_object,", to "DOM_object,Exist Flag Y/N,"
              sed -i "s|^$doms,|$doms,Y,$fullpath,Namespace,|g" "$workingdir/objects.csv"
            else
              sed -i "s|^$doms,|$doms,N,$fullpath,Namespace,|g" "$workingdir/objects.csv"
          fi
# Otherwise, if the object is not a namespace
       else        
          fullpath="`cat "$workingdir/objinfo.temp" |grep "Object path" |sed 's/Object path: //g'`"     
          if [ -e "$fullpath" ]
           then
# Pull DOM_Object from file to determine if orphaned
# Gather Object Class (Determines parsing)
# Parse for current DOM UUID in file, this gives us orphan information
objClass=`cat "$workingdir/objinfo.temp" |grep "Object class" |sed 's/Object class: //g'`
# if SWAP object
            if [ "$objClass" = "vmswap" ]
              then
                fileDOM=`cat "$fullpath" |grep objectID |awk -F\" '{print $2}' |sed 's|vsan://||g'`
            fi
# if VMDK object
            if [ "$objClass" = "vdisk" ]
              then
                fileDOM=`cat "$fullpath" |grep RW |awk -F\" '{print $2}' |sed 's|vsan://||g'`
            fi
# use sed to find/replace the DOM object from "DOM_object,", to "DOM_object,Exist Flag Y/N,"
                sed -i "s|^$doms,|$doms,Y,$fullpath,$fileDOM,|g" "$workingdir/objects.csv"
              else
                sed -i "s|^$doms,|$doms,N,$fullpath,Offline N/A,|g" "$workingdir/objects.csv"
          fi
       fi
    done
else
 echo "DOM UUID,Child Number,Component Type,State,FaultDomain,LSOM Component ID,Physical Disk ID,Physical Disk Owner,Disk Group UUID,," > "$workingdir/objects.csv"
# list all DOM objects, exlcude anything in the directory containing "host" or "disk", as these are not DOM objects, and begin a loop
      ls "$workingdir/DOMobjs/" |grep -vE "host|disk|exclude" |while read line
        do
# Print LSOM components and format as appropriate
# sed is used heavily here for formatting reasons, to pull out extraneous characters used for JSON formatting.
# unnecessary wording is pulled using sed find/replace: 's/find/replace/g', sometimes this is done more than once in a string 's/find/replace/g;s/find2/replace2/g'
          cat "$workingdir/DOMobjs/$line" |grep content |sed 's/,/\n/g' |grep -E "componentUuid|componentState|faultDomain|diskUuid|type" |grep -v StateTS |sed 's/\}//g;s/{//g;s/"//g;s/content: //g;s/,//g;' |sed 's/attributes: //g' |grep -vE "Configuration|RAID" |sed 's/Witness/Witness  /g' |sed 'N;N;N;N;s/\n/,/g' |sed "s/^/$line,/g" |sed 's/ type: /,/g;s/ child/child/g;s/ componentState: //g;s/ faultDomainId: //g;s/ componentUuid: //g;s/ diskUuid: //g'
# Print it all to /$workingdir/objects.csv
        done >> "$workingdir/objects.csv"
            
fi

}
                             




#FUNCTION to pull a specific DOM UUID
prettyprint_single(){
# list out only the user-provided DOM object
# this requires awk, as 'ls' for a specific file includes file path, and we don't want the entire path to the file
# Take user input and grab filename, and throw it to a loop
ls "$workingdir/DOMobjs/$userin" |awk -F\/ '{print $4}' |while read line
  do 
# Information flag set? (if set, use objtool to identify the object type and name (if possible)
     if [ "$info" = "1" ]
       then
         echo ""
         echo -e "DOM Object UUID: $line "
# Output result of objtool getAttr, redirect error to STDOUT for evaluation (if object returns I/O error)
         /usr/lib/vmware/osfs/bin/objtool getAttr -u "$userin" 2>&1 > "$workingdir/objinfo.temp"
# Check if the object is inaccessible, if so we need to skip data requests.
         if [ `grep -c "Input/output" "$workingdir/objinfo.temp"` -gt "0" ]
           then
             grep "Input/output" "$workingdir/objinfo.temp"
             echo "INACCESSIBLE - no data available"
# Otherwise, if the object is accessible
           else
# Determine File Path
# If the object is a namespace, we need to compile this
             if [[ "`cat "$workingdir/objinfo.temp" |grep "Object class" |awk -F\: '{print $2}'`" = " vmnamespace" ]]
               then
                 partpath="`cat "$workingdir/objinfo.temp" |grep "Object path" |awk -F\: '{print $2":"$3}'`"
                 friendly="`cat "$workingdir/objinfo.temp" |grep friendly |awk -F\: '{print $2}'`"
                 objpath="$partpath$friendly"
# If not a namespace, just grab the file path and do a bit of formatting to remove "Object path:"
               else
                 objpath="`cat "$workingdir/objinfo.temp" |grep "Object path" |sed 's/Object path: //g'`"
             fi
             echo -e "File Path:\t$objpath"
             echo -en "Object Type:\t "
             cat "$workingdir/objinfo.temp" |grep "Object class" |sed 's/Object class: //g'
             rm "$workingdir/objinfo.temp"
          fi
       echo "- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -"       
# If the info flag is not turned on, just return the DOM object UUID
     else
       echo "DOM Object: $line"
       echo "- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -"
     fi
# Print LSOM components and format as appropriate
# sed is used heavily here for formatting reasons, to pull out extraneous characters used for JSON formatting.
# unnecessary wording is pulled using sed find/replace: 's/find/replace/g', sometimes this is done more than once in a string 's/find/replace/g;s/find2/replace2/g'
# Yes, these sed statements are crazy.
     echo "LSOM Components:"
     cat "$workingdir/DOMobjs/$line" |grep content |sed 's/,/\n/g' |grep -E "componentUuid|componentState|faultDomain|diskUuid|type" |grep -v StateTS |sed 's/\}//g;s/{//g;s/"//g;s/content: //g;s/,//g;' |sed 's/attributes: //g' |grep -vE "Configuration|RAID" |sed 's/Witness/Witness  /g' |sed 'N;N;N;N;s/\n/ /g'
     echo "---------------------------------------------------------------------------------------------------------------------------------------------------------------------"
     echo ""
# Finish the loop through DOM object provided, and dump output to $workingdir/pretty_uuid.txt temporarily
  done > "$workingdir/pretty_uuid.txt"
# set "infile" variable for hostcorr FUNCTION to associate fault domains to Hostnames for this item
  infile="$workingdir/pretty_uuid.txt"
# LEGACY Call faultcorr function
# LEGACY  faultcorr
# call hostcorr function
   hostcorr
# Print to screen
  cat "$workingdir/pretty_uuid.txt"
# remove temp file
  rm  "$workingdir/pretty_uuid.txt"
}

#FUNCTION to validate user input
# meant to confirm user input is actually present in DOM, so that we are not provided a disk, host, etc..
validate_userDOM (){
# if a grep in all known DOM UUID's returns zero lines, this is not a DOM object
if [ `cmmds-tool find -f json -t DOM_OBJECT |grep uuid |grep -w $userin |wc -l` -le "0" ]
  then
  echo "The input provided is not a valid DOM object in CMMDS, please double-check the value and try again"
  exit
fi
}



#FUNCTION to correlate fault_domains
faultcorr(){
# pull all filenames beginning with "host" from "$workingdir/DOMobjs", begin a loop
ls "$workingdir/DOMobjs/" |grep "^host" |while read line
  do
# Define faultid for replacement/augment
    faultid=`echo "$line" |awk -F\_ '{print $2}'`
# File contains hostname, so cat it and define hostname as hostn for replacement/augment
    hostn=`cat "$workingdir/DOMobjs/$line"`
# In-place replacement into "$infile", appending the hostname in parentheses
    sed -i "s/$faultid/$faultid ($hostn)/g" "$infile"
  done
}

#FUNCTION to correlate hostname
#replaces FUNCTION faultcorr
hostcorr(){
# faultcorr was found to have various problems with fault-domain logic, so it is being replaced. 
# Replacement hostcorr will correlate all disks to their owner by looking up the "owner" line in CMMDS. As long as this exists and the disk_* files have been created in "$workingdir/DOMobjs" this should succeed
# Find all disks (gather_DISKS has been done at this point)
ls "$workingdir/DOMobjs/" |grep ^disk_ |sed 's/disk_//g' |while read line
# Correlate all disks to their owning host
  do 
    cmmds-tool find -f json -t DISK -u $line |grep -F '   "uuid": ' -A1
  done |sed 's/\,//g;N;s/\n/\t/g' |while read diskown
    do 
      # Store disk UUID
      disk=`echo $diskown |awk -F\" '{print $4}'`
      # Store owner UUID
      ownhost=`echo $diskown |awk -F\" '{print $8}'`
      # Correlate to Hostname entry in CMMDS
      hostn=`cmmds-tool find -f json -t HOSTNAME -u $ownhost |grep "content" |awk -F\" '{print $6}'`
      sed -i "s|diskUuid: $disk|diskUuid: $disk\tOwning Host: $hostn |g" "$infile"
    done
  
 
# Output a file for this lookup




}


#FUNCTION to correlate fault_domains in csv
faultcorr_csv(){
# pull all filenames beginning with "host" from /tmp/DOMobjs, begin a loop
ls "$workingdir/DOMobjs/" |grep "^host" |while read line
  do
# Define faultid for replacement/augment
    faultid=`echo "$line" |awk -F\_ '{print $2}'`
# File contains hostname, so cat it and define hostname as hostn for replacement/augment
    hostn=`cat "$workingdir/DOMobjs/$line"`
# In-place replacement into "$infile", appending the hostname and adding appropriate commas
    sed -i "s/$faultid/$faultid,$hostn/g" "$infile"
  done
}


#FUNCTION to correlate disk_to_host in csv file
# replaces FUNCTION faultcor_csv
# Created to handle fault-domains containing multiple hosts, script will correlate which disks physically reside in which Host (per CMMDS) and then find/replace in the CSV.
# Find all disks (gather_DISKS has been done at this point)
hostcorr_csv(){
# Build Cache Tier Exclusion list ($workingdir/DOMobjs/excluse_cachetier) for later use
cmmds-tool find -f json -t DISK |grep content |sed s'/,/\n/g' |grep ssdUuid |awk -F\" '{print $4}' |sort |uniq > "$workingdir/DOMobjs/exclude_cachetier"
ls "$workingdir/DOMobjs/" |grep ^disk_ |sed 's/disk_//g' |while read line
# Correlate all disks to their owning host
  do
    cmmds-tool find -f json -t DISK -u $line |grep -F '   "uuid": ' -A1
  done |sed 's/\,//g;N;s/\n/\t/g' |while read diskown
    do
       # Store disk UUID
       disk=`echo $diskown |awk -F\" '{print $4}'`
       # Store owner UUID
       ownhost=`echo $diskown |awk -F\" '{print $8}'`
       # Correlate to Hostname entry in CMMDS
       hostn=`cmmds-tool find -f json -t HOSTNAME -u $ownhost |grep "content" |awk -F\" '{print $6}'`
       
       # Find Diskgroup (if 6.0 or above)
         diskgroup=`cmmds-tool find -f json -t DISK -u $disk |grep content |sed 's/,/\n/g' |grep ssdUuid |awk -F\" '{print $4}'`
       # Need to exclude cache tier disks here to avoid duplicate replacement in CSV file
       
         if  [ "`cat "$workingdir/DOMobjs/exclude_cachetier" |grep $disk |wc -l`" -eq 0 ]
           then
           sed -i "s|$disk|$disk,$hostn,$diskgroup,,|g" "$infile"
         fi
         
    done
}                                                      

                



#FUNCTION to gather disk stats
#Meant to mimic disks_stats from RVC
disks_stats(){
# List all disks in VSAN cluster currently
ls "$workingdir/DOMobjs/disk"* |while read line
  do
# Pull the first "uuid" field (as these may not match) and its "owner" field, and put them on one line (this will be combined later)
    cat "$line" |grep -E -m1 "uuid" -A1 |sed 's/"//g;s/,//g' |sed 'N;s/\n//g'
# Gather all disk information from the various disk-related fields in CMMDS, and parse them for only:
#  - capacity
#  - isSsd
#  - ssdUuid (disk group equivalent)
#  - capacityUsed (disk usage info)
#  - healthFlags (disk health)
#  - uuid (DISK object UUID)
#  - owner (DISK owner, physical Host)
# Output all disk information for formatting twice, once in pretty-print and once in CSV. ("$workingdir/disks_stats.txt", "$workingdir/temp_disks_stats.csv"
    cat "$line" |grep "content" |sed 's/,/\n/g;s/\"//g;s/  content: //g;s/{//g' |grep -E "capacity|isSsd|ssdUuid|capacityUsed|healthFlags|uuid|owner" |grep -v "capacityReserved" |sort |uniq |sed 'N;N;N;N;s/\n//g'
# Awk is used here to do disk math, and determine what percentage of disk is utilized
  done |sed 'N;s/\n//g' |awk '{print $1" "$2" "$9" "$10" "$3" "$4" "$13" "$14" "$11" "$12" "$7""$8"\t"$5" "$6"\t Space Consumed: "( ($8 / $6) * 100)"%"}' |tee "$workingdir/disks_stats.txt" > "$workingdir/temp_disks_stats.csv"
# Additional formatting is done for pretty-print, including fancy lines and replacing "healthFlags: 0" with "HEALTHY", then relacing "healthFlags: " that are left over with "Unhealthy: ", as only non-zero matches will be left  
  cat "$workingdir/disks_stats.txt" |sed 's/isSsd: 1/type: SSD    /g;s/isSsd: 0/type: Non-SSD/g'|sed 's/capacityUsed:0/capacityUsed:0         /g' |sed 's/healthFlags: 0/HEALTHY/g' |sed 's/healthFlags: /Unhealthy: /g' |sort -k5 -k7 -rk9 > "$workingdir/disks_stats.txt"

# Lines of formatting, all output to /tmp/disks_stats_pretty.txt
  echo "-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------" > "$workingdir/disks_stats_pretty.txt"
  echo "|     PHYSICAL DISK UUID              |    STATE     |         DISK  OWNER (HOST)           |            DISK GROUP UUID           |  TYPE   |    BYTES USED    |    CAPACITY    | % USED       |" >> "$workingdir/disks_stats_pretty.txt"
  echo "-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------" >> "$workingdir/disks_stats_pretty.txt"
# Remove additional information that is redundant per the title bars, replace with pipe-command formatting as in RVC
  cat /tmp/disks_stats.txt |sed 's/uuid: /\|/g;s/owner:/\|/g;s/ssdUuid:/\|/g;s/type:/\|/g;s/capacityUsed:/\|/g;s/capacity:/\|/g;s/Space Consumed:/\|/g' |sed 's/HEALTHY/\|HEALTHY      /g;s/0%/0%   /g;s/$/\t\|/g' >> "$workingdir/disks_stats_pretty.txt"
  echo "-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------" >> "$workingdir/disks_stats_pretty.txt"
# Print pretty-print file to screen
  cat "$workingdir/disks_stats_pretty.txt"
# Remove temp file
  rm "$workingdir/disks_stats.txt"
# Begin CSV output
  echo "OBJECT UUID,STATE,OBJECT OWNER,SSD DISK GROUP,TYPE,BYTES USED,CAPACITY,% USED "> "$workingdir/disks_stats.csv"
# Formatting to allow for CSV
# Some sed portions are very specific in spaces and tabs due to formatting of output for pretty-print, output to $workingdir/disks_stats.csv
  cat "$workingdir/temp_disks_stats.csv" | sed 's/uuid: //g;s/ healthFlags: 0/,HEALTHY/g;s/healthFlags:/Unhealthy: /g;s/ owner: /,/g;s/ ssdUuid: /,/g;s/ isSsd: /,/g;s/ capacityUsed:/,/g;s/\tcapacity: /,/g' |sed 's/\t Space Consumed: /,/g' >> "$workingdir/disks_stats.csv" 
# Remove temp file
  rm "$workingdir/temp_disks_stats.csv"
}


#FUNCTION to provide all VM information
# Meant to provide output similar to vm_info
# Feeds in "vmxpath" as variable from DO WORK section
vminfo() {
echo ""
echo "Collecting object information for the VM from: $vmxpath"
#get Info (Currently disabled, too verbose)
#info="1"
#Define Directory for reading files
vmpath=`dirname "$vmxpath"`
# Get VM Namespace Information
namespaceUUID=`basename "$vmpath"`
#Prepare for pretty-print parsing
userin=`echo $namespaceUUID`
echo "=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-"
echo "VIRTUAL MACHINE NAMESPACE OBJECT"
echo "=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-"
gather_DOM_single
#Namespace to PrettyPrint
prettyprint_single
# Get VSWP information
cat "$vmxpath" |grep vswp |awk -F\" '{print $2}' |while read line;
  do
echo "=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-"
    echo "SWAP FILE: $line"
echo "=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-"
    userin=`cat "$line" |grep objectID |awk -F\/ '{print $3}' |sed 's/"//g'`
    gather_DOM_single
    prettyprint_single
  done
# Get vDisk information
cat "$vmxpath" |grep vmdk |awk -F\" '{print $2}' |while read line;
  do
    echo "=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-"
    echo "VMDK DISK FILE: $line"
    echo "=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-"
    if [[ ${line:0:1} == "/" ]]
      then
        userin=`cat "$line" |grep RW |awk -F\/ '{print $3}' |sed 's/"//g'`
        gather_DOM_single
        prettyprint_single
      else
        userin=`cat "$vmpath/$line" |grep RW |awk -F\/ '{print $3}' |sed 's/"//g'`
        gather_DOM_single
        prettyprint_single
    fi                    
  done
                    



}


#FUNCTION to check DOM object health status
# Relies upon prettyprint_csv having been run successfully (Creates CSV file of objects first for ease of processing)
# Meant to provide output similar to vsan.check_state
check_state () {
#Get all DOM objects from gather_DOM, throw them to a loop
ls "$workingdir/DOMobjs/" |grep -vE "host|disk|exclude" |while read line
# Compare all DOM objects for accessible objects vs total objects
  do
    totalLSOMs=`cat "$workingdir/objects.csv" |grep "$line" |wc -l`
    accessibleLSOMs=`cat "$workingdir/objects.csv" |grep "$line" |awk -F\, '{ if ( $4 == 5 ) print }' |wc -l`
    percentavail=`echo "$accessibleLSOMs $totalLSOMs" |awk '{ print ( $1 / $2 ) *100 }' |cut -c-3 |sed 's/\.$//g'`

# Theory flag check
# if set to true, use lower entry-point and do not query objtool, as this is a theoretical failure
    if [ "$theoretical" = "1" ]
      then
        if [ "$percentavail" -lt "50" ]
          then
            echo "Object $line may become inaccessible"
        fi
      else
# Check every object with less than 100% of objects available
        if [ "$percentavail" -lt "100" ]
          then
# Determine if file is accessible or not using objtool for validation
# Output result of objtool getAttr, redirect error to STDOUT for evaluation (if object returns I/O error)
            /usr/lib/vmware/osfs/bin/objtool getAttr -u "$line" 2>&1 > "$workingdir/objinfo.temp"
# If inaccessible in objtool, we can safely assume the object is offline.
              if [ `grep -c "Input/output" "$workingdir/objinfo.temp` -gt "0" ]
                then
                echo "Detected object $line as inaccessible"    
              fi
# cleanup
           rm "$workingdir/objinfo.temp"
        fi
    fi
  done


}


#FUNCTION to whatif fail a device
# Relies upon prettyprint_csv having been run successfully (Creates CSV file of objects first for ease of processing
# used to mimic what if fails in RVC
# finds all entries for the UUID, replaces state "5" with "9"
# Modifies CSV file from prettyprint_csv with the above find/replace, then check_state function is called against modified CSV file
whatif_sed () {
# Cat out the file, grep for userin and throw to a loop
# While reading each matching entry, remove it from the file completely, and replace it with a state "9" at the bottom of the file
cat "$workingdir/objects.csv" |grep "$userin" | while read line
  do 
    sed -i "s/$line//g" "$workingdir/objects.csv"
    echo "$line" |sed 's/,5,/,9,/g' >> "$workingdir/objects.csv"
done
}

#FUNCTION to print bytestoSync values, resync information
# used to mimic vsan.resync_dashboard
resync() {
#If old tmp_bytesTS exists, remote it
if [ -e "$workingdir/tmp_bytesTS" ]
  then
      rm "$workingdir/tmp_bytesTS"
fi
#Get all DOM objets, throw them to a loop
ls "$workingdir/DOMobjs/" |grep -vE "host|disk|exclude" |while read line
  do
# Validate object has "bytesToSync" lines
    if [ `cat "$workingdir/DOMobjs/$line" |grep "content" |sed 's/,/\n/g' |grep bytesToSync |awk -F": " '{print $2}' |wc -l` -gt 0 ]
      then
# Find the name of the object
      	 echo -en "$line=" >> "$workingdir/tmp_bytesTS"
# Gather all bytes to sync lines for the object, set equal to "bytesTS" variable
        cat "$workingdir/DOMobjs/$line" |grep "content" |sed 's/,/\n/g' |grep bytesToSync |awk -F": " '{print $2}' |while read line
# Convert them to GiB from bytes
        do 
          echo "`expr $line / 1073741824`"
        done |awk '{s+=$1} END {print s}' >> "$workingdir/tmp_bytesTS"
    fi
  done
# All objects and resync in GB are now stored in "$workingdir/tmp_bytesTS", we will use this file
# Need to correlate all UUID's to DOM_Object for non-zero resync, use non-zero filter first to avoid undue cost on osfs
# use awk to separate non-zeros
if [ -e "$workingdir/tmp_bytesTS" ]
then
  cat "$workingdir/tmp_bytesTS" | awk -F\= '{ if ( $2 > 0 ) print $1}' |while read doms
    do
# Temporarily capture objtool output for parsing
      /usr/lib/vmware/osfs/bin/objtool getAttr -u $doms > "$workingdir/objinfo.temp"
# Determine whether the object is a namespace, or other, and evaluate it with an if-exist
      if [[ "`cat "$workingdir/objinfo.temp" |grep "Object class" |awk -F\: '{print $2}'`" = " vmnamespace" ]]
        then
# Define "friendly" variable to print out name of namespace "folder"
            friendly="`cat "$workingdir/objinfo.temp" |grep friendly |awk -F\: '{print $2}'`"
# Gather path to object (will simply be vsan root for namespace)
            vsanpath="`cat "$workingdir/objinfo.temp" |grep "Object path" |sed 's/Object path: //g'`"
            fullpath="`echo "$vsanpath$friendly"`"
        else
            fullpath="`cat "$workingdir/objinfo.temp" |grep "Object path" |sed 's/Object path: //g'`"
      fi
      sed -i "s|$doms|$fullpath|g" "$workingdir/tmp_bytesTS"
    done
fi
# Formatting for print to screen
# Take items in $workindir/tmp_bytesTS, and pretty-print them using AWK with "=" as a separator (least likely to be used in VM name)
echo
echo
echo "The following DOM Objects have pending bytes to sync:"
echo "=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-="
echo -e "Filename\t\t\t\t\t\t\t |GB to Sync"
echo "---------------------------------------------------------------------------------------------"
if [ -e "$workingdir/tmp_bytesTS" ]
  then
  cat "$workingdir/tmp_bytesTS" |while read syncval
  do
    filen=`echo $syncval |awk -F\= '{print $1}'`
    syncGB=`echo $syncval |awk -F\= '{print $2}'`
# Double Check that bytesTS is not 0
    if [ $syncGB -gt "0" ]
      then
      echo -e "`basename "$filen"`\t$syncGB"| awk  '{ printf "%-64s %-120s\n", $1,"|" $2}'
    fi
  done
echo "---------------------------------------------------------------------------------------------"
else
  echo
  echo "CMMDS reports no objects with Bytes to Sync"
  echo
  echo "---------------------------------------------------------------------------------------------"
fi
 
#cleanup
if [ -e "$workingdir/tmp_bytesTS" ]
  then
      rm "$workingdir/tmp_bytesTS"
fi
      
}


#FUNCTION to owner-abdicate
abdicate() {
# DOM Object information is already cached from previous function
# Gather current DOM OWNER from $workingdir/UUID
owner=`cat "$workingdir/DOMobjs/$userin" |grep -F '   "uuid"' -A1 |sed 'N;s/\n//g' |awk -F\" '{print $8}'`
#echo
#echo "Current DOM Owner: $owner"
locUUID="`cmmds-tool whoami`"
#echo "Local  Host  UUID: $locUUID"
#echo
# See if DOM ownerhsip is held by another Host
#   If so, direct user to other Host
#   If not, abdicate the object
 
if [ "$owner" != "$locUUID" ]
  then
    #Owner is a different VSAN Host, attempt to lookup Hostname. Store as DOMown variable.
    DOMown=`cmmds-tool find -f json -t HOSTNAME -u $owner |grep content |awk -F\" '{print $6}' `
    echo
    echo "Error: owner abdication must be attempted from the current DOM owner."
    echo "This Host, $locUUID (`hostname`), does not own the specified object. Ownership currently belongs to: $owner ($DOMown)"
    echo 
    echo "Please retry this command from the DOM owner:"
    echo "vsish -e set /vmkModules/vsan/dom/ownerAbdicate \"$userin\""
    echo
  else
    echo "Issuing owner-abdicate against $userin"
    vsish -e set /vmkModules/vsan/dom/ownerAbdicate "$userin"
fi
}



############# DO WORK ################

         
####### Helpfile     #######
#HELP, -h , --help, Display help menu
### display help ###
### Help file is self-generating, based on flag line beginning "#HELP"
if [ "$1" = "-h" ] || [ "$1" = "--help" ]
  then
  help
  exit
fi

      
##### Pretty Print #####
#HELP, -p , --pretty, Pretty-print all DOM/LSOM correlations. May also specify UUID: DOM_tool.sh -p <uuid>
### Print out all LSOM linkages with pretty formatting and ownership information
### includes: object type, componentState, faultDomain, componentUuid, diskUuid
if [ "$1" = "-p" ] || [ "$1" = "--pretty" ]
  then
# check if UUID has been provided by user (non-default)
# If no UUID provided, gather all and output to $workingdir/objects.txt
  if [ -z ${2+x} ]
    then
    sizecheck
    foldercheck
    gather_DOM
    gather_HOSTS
    gather_DISKS
    prettyprint
    infile="$workingdir/objects.txt"
    hostcorr
    echo "All DOM/LSOM relations have been dumped to $workingdir/objects.txt"
    exit
# if UUID is provided by user, set this equal to variable "userin" and run FUNCTION prettyprint_single
  else
    userin=`echo $2`
    validate_userDOM
    foldercheck
    gather_DOM_single
    gather_HOSTS
    gather_DISKS
    prettyprint_single
    exit 
  fi
fi

##### Pretty Print Info#####
#HELP, -pi, --prettyinfo, Similar to -p   Provides filename/filepath and type (objtool).
### Print out LSOM linkages with pretty formatting and object information
### includes: DOM information, object type, componentState, faultDomain, componentUuid, diskUuid
if [ "$1" = "-pi" ] || [ "$1" = "--prettyinfo" ]
  then
  if [ -z ${2+x} ]
    then 
      echo "No user input provided, please provide a DOM object from CMMDS"
      echo "Usage: DOM_tool.sh -pi <DOM uuid>"
      exit
    else
      userin=`echo $2`
      validate_userDOM
      foldercheck
      gather_DOM_single
      gather_HOSTS
      gather_DISKS
      info="1"
      gather_DISKS
      prettyprint_single
      exit
  fi
fi                                                                        


##### Disk_Stats #####
#HELP, -d , --disks, Print all Disk Utilization Statistics
### Print out all Disk-to-Host linkages with pretty formatting and space utilization information
### includes: 
if [ "$1" = "-d" ] || [ "$1" = "--disks" ]
  then
  foldercheck
  gather_DISKS
  disks_stats
  exit
fi


#### Run -pi on ALL cluster objects ####
#HELP, -a , --all, Execute 'DOM_tool.sh -pi' against all DOM objects. Saves to file 'cluster_objects.txt'
### Runs single-item pretty-print (with info) against all DOM objects
### outputs to $workingdir/clusterinfo.txt
if [ "$1" = "-a" ] || [ "$1" = "--all" ]
  then
  sizecheck
  rm "$workingdir/cluster_objects.txt"
  echo "You have elected to output all cluster object data. This may take some time..."
  counter="1"
  DOMtotal=`cmmds-tool find -f json -t DOM_OBJECT |grep uuid |awk -F\" '{print $4}' |wc -l`
# Gather all DOM objects for count
cmmds-tool find -f json -t DOM_OBJECT |grep uuid |awk -F\" '{print $4}' |while read DOM;
    do
    
      echo -en "\rProcessing record $counter of $DOMtotal"
      userin="`echo $DOM`"   
      foldercheck
      gather_DOM_single
      gather_HOSTS
      gather_DISKS
      info="1"
      prettyprint_single >> "$workingdir/cluster_objects.txt"
      counter="`expr $counter + 1 `"
    done
    rm -r "$workingdir/DOMobjs/"*;rmdir "$workingdir/DOMobjs/"
    echo ""
    echo "Complete."
    echo "Full cluster information can be found in $workingdir/cluster_objects.txt"
    exit
fi
      
#### VM INFO ####
#HELP, -v , --vminfo, Gather objects for a specific Virtual Machine: DOM_tool.sh -v <Path To VMX File>
if [ "$1" = "-v" ] || [ "$1" = "--vminfo" ]
  then
    if [ -z ${2+x} ]
      then
        echo "No user input provided, please specify the path to the VMX in question on VSAN"
        echo "Usage: DOM_tool.sh -v /vmfs/volumes/vsanDatastore/myVM/myVM.vmx"
        exit
      else
        lncheck="`dirname $2`"
        vmxname="`basename $2`"
        if [ -h $lncheck ]
          then
          vsandir="`dirname $lncheck`"
          nsUUID="`ls -l $lncheck |awk '{print $11}'`"
          vmxpath="`echo $vsandir/$nsUUID/$vmxname`"
        else
          vmxpath=`echo $2`
        fi
	foldercheck
        vminfo
    
    fi                                                  
    exit
fi

#### Prettyprint_csv ####
#HELP, -c , --csv, Prints to CSV. Provides minimal object data (Faster). Outputs to 'objects.csv'
if [ "$1" = "-c" ] || [ "$1" = "--csv" ]
  then
      sizecheck
      foldercheck
      gather_DOM
      gather_HOSTS
      gather_DISKS
      prettyprint_csv
      infile="$workingdir/objects.csv"
      hostcorr_csv
      echo "All DOM/LSOM relations have been dumped to $workingdir/objects.csv"
      exit
fi

#### Prettyprint_csv_info ####
#HELP, -ci, --csvinfo, Similar to '-c'   Provides verbose object data (Slower). Outputs to 'objects.csv'
if [ "$1" = "-ci" ] || [ "$1" = "--csvinfo" ]
  then
    sizecheck
    foldercheck
    gather_DOM
    gather_HOSTS
    gather_DISKS
    info="1"
    prettyprint_csv
    infile="$workingdir/objects.csv"
    hostcorr_csv
    echo "All DOM/LSOM relations have been dumped to $workingdir/objects.csv"
    exit
fi
                                                        



##### VSAN Check State#####
#HELP, -cs, --checkstate, Determine object health across the cluster, prints inaccessible items to STDOUT
### runs CSV function, then uses output file to determine the health of every object based on strict 50% logic of available LSOM components
### 
if [ "$1" = "-cs" ] || [ "$1" = "--checkstate" ]
  then
# Create CSV file
    echo "Evaluating the cluster for inaccessible VSAN objects..."
    sizecheck
    foldercheck
    gather_DOM
    gather_HOSTS
    gather_DISKS
    prettyprint_csv 2>&1 >/dev/null
    infile="$workingdir/objects.csv"
    hostcorr_csv
# Gather all DOM objects
    echo "Inaccessible objects:"
    echo "------------------------------------------------------------"
    check_state          
    echo ""
    exit
fi
                                                                          

                                                                                                      
##### Whattif Fails #####
#HELP, -w , --whatif, Assess object health across the cluster in the event of a host/disk-group/disk failure. 
### runs CSV function, then uses output file to determine the health of every object based on strict 50% logic of available LSOM components
###
if [ "$1" = "-w" ] || [ "$1" = "--whatif" ]
  then
    if [ -z ${2+x} ]
      then
        echo "No user input provided, please provide a DOM object from CMMDS"
        echo "Usage: DOM_tool.sh -w <uuid>"
        exit
      else
        userin=`echo $2`
        theoretical="1"
        sizecheck
        foldercheck
        gather_DOM
        gather_HOSTS
        gather_DISKS
        prettyprint_csv 2>&1 >/dev/null
        infile="$workingdir/objects.csv"
        hostcorr_csv
        echo 
        echo "Assuming there is a failure of $userin, the following DOM objects may be affected:"
        echo "--------------------------------------------------------------------------------------------------------------"
        whatif_sed
        check_state                                                         
        echo
        exit
    fi
fi
                                                                                                            
##### Resync Dashboard #####
#HELP, -r , --resyncinfo, Prints all DOM objects that have bytes to resync, and the space resycning.
### finds all "bytestoSync" values per DOM object and totals them, then converts to GiB.
###
if [ "$1" = "-r" ] || [ "$1" = "--resyncinfo" ]
  then
    sizecheck
    foldercheck
    gather_DOM
    gather_HOSTS
    gather_DISKS
    resync
    exit 
fi                                                                                                                              

####### Owner Abdicate DOM    #######
#HELP, -ab, --abdicate, Issues owner abdication request against a specified DOM object.
if [ "$1" = "-ab" ] || [ "$1" = "--abdicate" ]
  then
# Check if user input has been provided
    if [ -z ${2+x} ]
      then
      echo "No user input provided, please provide a DOM object from CMMDS"
      echo "Usage: DOM_tool.sh -ab <DOM uuid>"
      exit
    else
# Store user input as another variable
      userin=`echo $2`
# Create Folder
      foldercheck
# Confirm this is a DOM object
      validate_userDOM
# Collect single DOM object info to $workingdir/DOMobjs/
      gather_DOM_single
# Call abdication function
      abdicate
      exit
    fi
                                                  

# Store user input as another variable
# Check if this Host owns the object at a DOM level
# If owned
## Abdicate DOM, report success
# If not owned:
## Look at the HOSTNAME record of the owner, store as a variable
## Suggest command be re-run on object's DOM Owner


fi



# Catch-All
echo "No option selected, or option is invalid. Please select a valid option from the below.";echo
help


           
