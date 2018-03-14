oracleDbdstPrepare(){
i=0
voln=4
autotcvol=autotcvol
dg=(${dbdata_array[0]} ${archive_array[0]})
size0=(${dbdata_array[2]} ${archive_array[2]})
for size in $[${dbdata_array[2]}*$voln] $[${archive_array[2]}*$voln]
do
        RExec root $NODE1 "vxassist -g ${dg[$i]} maxsize"
        freesize=`echo "$out"|grep -oP "\d+(?=\w+\))"|cut -d . -f 1`
        if [ -n "$freesize" ] && [ "$freesize" -lt $size ]
        then
                adddisk=`getDiskBySizeWithPath $NODE1 "$size" local` || exit 1
                RExec root $NODE1 "vxdg -g ${dg[$i]} adddisk $adddisk"
        fi
        [ ${dbdata_array[0]} = ${archive_array[0]} ] && [ $i = 0 ] && seq="1 2 3 4" || seq="5 6 7 8"
        for j in $seq
        do
                makeVolBySize $NODE1 ${dg[$i]} $autotcvol$j "${size0[$i]}"M
                RExec root $NODE1 "vxedit -g ${dg[$i]} set user=oracle $autotcvol$j"
        done
        i=$[$i+1]
done
RExec root $NODE1 "vxedit -g ${dbdata_array[0]} set user=oracle ${dbdata_array[1]}"
RExec root $NODE1 "vxedit -g ${archive_array[0]} set user=oracle ${archive_array[1]}"
}

oracleDbdst(){
local i out_list dbffileno
RExec $oracle $NODE1 "NOEXIT:/opt/VRTSdbed/bin/dbed_update -S \$ORACLE_SID -H \$ORACLE_HOME"
if [ $? -eq 1 ]
then
        oLog "des" "Waring: Trying to fix it through workaround"
        RExec root $NODE1 'NOEXIT:rm -f /var/vx/vxdba/rep_loc;/opt/VRTSdbed/bin/vxdbd stop;rm -rf /var/vx/vxdba/auth /opt/VRTSdbed/at-broker /var/VRTSat /var/VRTSat_lhc;echo "AUTHENTICATION=no" > /etc/vx/vxdbed/admin.properties;/opt/VRTSdbed/bin/vxdbd start'
	sleep 20
        RExec $oracle $NODE1 "/opt/VRTSdbed/bin/dbed_update -S \$ORACLE_SID -H \$ORACLE_HOME"
fi
RExec $oracle $NODE1 "/opt/VRTS/bin/dbdst_admin -S \$ORACLE_SID -o list"
out_list="$out"
for i in FAST MEDIUM SLOW
do
        echo "$out_list"|grep  "^Name = $i" > /dev/null 2>&1 || RExec $oracle $NODE1 "/opt/VRTS/bin/dbdst_admin -S \$ORACLE_SID -o addclass=$i:'$i Storage'"
done
RExec $oracle $NODE1 "/opt/VRTS/bin/dbdst_admin -S \$ORACLE_SID -o list"
stopGroupAny $NODE1 $oracle_group

oLog des "Converting volume ${dbdata_array[1]} to volume set"
RExec $oracle $NODE1 "/opt/VRTS/bin/dbdst_convert -S \$ORACLE_SID -M /dev/vx/dsk/${dbdata_array[0]}/${dbdata_array[1]} -v autotcvol1,autotcvol2"
RExec root $NODE1 "/usr/sbin/vxvset -g ${dbdata_array[0]} list ${dbdata_array[1]}" "autotcvol1,autotcvol2"

oLog des "Converting volume ${archive_array[1]} to volume set"
RExec $oracle $NODE1 "/opt/VRTS/bin/dbdst_convert -S \$ORACLE_SID -M /dev/vx/dsk/${archive_array[0]}/${archive_array[1]} -v autotcvol5,autotcvol6"
RExec root $NODE1 "/usr/sbin/vxvset -g ${archive_array[0]} list ${archive_array[1]}" "autotcvol5,autotcvol6"
startGroupAny $NODE1 $oracle_group
RExec root $NODE1 "/opt/VRTS/bin/fsvoladm list ${dbdata_array[4]}"
RExec root $NODE1 "/opt/VRTS/bin/fsvoladm list ${archive_array[4]}"

oLog des "Define Classes for all volumes in volume set"
RExec $oracle $NODE1 "/opt/VRTS/bin/dbdst_classify -S \$ORACLE_SID -M /dev/vx/dsk/${dbdata_array[0]}/${dbdata_array[1]} -v autotcvol1:FAST"
RExec $oracle $NODE1 "/opt/VRTS/bin/dbdst_classify -S \$ORACLE_SID -M /dev/vx/dsk/${dbdata_array[0]}/${dbdata_array[1]} -v autotcvol2:SLOW"
RExec $oracle $NODE1 "/opt/VRTS/bin/dbdst_classify -S \$ORACLE_SID -M /dev/vx/dsk/${dbdata_array[0]}/${dbdata_array[1]} -v ${dbdata_array[1]}-b4vset:MEDIUM"
RExec $oracle $NODE1 "/opt/VRTS/bin/dbdst_show_fs -S \$ORACLE_SID -m ${dbdata_array[4]}" "FAST,SLOW,MEDIUM"
RExec $oracle $NODE1 "/opt/VRTS/bin/dbdst_classify -S \$ORACLE_SID -M /dev/vx/dsk/${archive_array[0]}/${archive_array[1]} -v autotcvol5:FAST"
RExec $oracle $NODE1 "/opt/VRTS/bin/dbdst_classify -S \$ORACLE_SID -M /dev/vx/dsk/${archive_array[0]}/${archive_array[1]} -v autotcvol6:SLOW"
RExec $oracle $NODE1 "/opt/VRTS/bin/dbdst_classify -S \$ORACLE_SID -M /dev/vx/dsk/${archive_array[0]}/${archive_array[1]} -v ${archive_array[1]}-b4vset:MEDIUM"
RExec $oracle $NODE1 "/opt/VRTS/bin/dbdst_show_fs -S \$ORACLE_SID -m ${archive_array[4]}" "FAST,SLOW,MEDIUM"
RExec $oracle $NODE1 "/opt/VRTSdbed/bin/dbed_update -S \$ORACLE_SID -H \$ORACLE_HOME"

oLog des "Define Policy and check if files move for ${dbdata_array[4]}"
RExec $oracle $NODE1 "/opt/VRTS/bin/fsmap $dbdata_path/*.ctl"

RExec $oracle $NODE1 "/opt/VRTS/bin/dbdst_preset_policy -S \$ORACLE_SID -d ${dbdata_array[4]} -P FAST=*.ctl"
RExec $oracle $NODE1 "/opt/VRTS/bin/dbdst_preset_policy -S \$ORACLE_SID -l -d ${dbdata_array[4]}"
RExec $oracle $NODE1 "/opt/VRTS/bin/fsmap $dbdata_path/*.ctl"
if echo "$out"|grep autotcvol1 > /dev/null 2>&1
then
        oLog des "Part of the ctl files have move to autotcvol1"
else
        oLog error "There must be part of ctl files on autotcvol1"
        myexit 1
fi

oLog des "execute sql sentences to create tables"
cat $BASE/etc/dbdst_pre.sql|awk '{gsub("_PATH_","'$dbdata_path'");print}' > $BASE/tmp/dbdst_pre.$PID.sql
scp -p $BASE/tmp/dbdst_pre.$PID.sql $NODE1:/tmp/
LExec "cat $BASE/tmp/dbdst_pre.$PID.sql;rm -f $BASE/tmp/dbdst_pre.$PID.sql"
RExec root $NODE1 "ls -l /tmp/dbdst_pre.$PID.sql"
RExec $oracle $NODE1 "sqlplus / as sysdba @/tmp/dbdst_pre.$PID.sql"
RExec root $NODE1 "rm -f /tmp/dbdst_pre.$PID.sql"
RExec $oracle $NODE1 "/opt/VRTSdbed/bin/dbed_update -S \$ORACLE_SID -H \$ORACLE_HOME"
oLog des "Modify create time of below dbf file in case below dbf file is created one day before"
RExec root $NODE1 "ls -l /archive | head -5"
dbffile=`echo "$out"|grep -oP "[^ ]+dbf"|xargs -n 100`
for i in $dbffile
do
	RExec root $NODE1 "touch -t 200207010800.01 ${archive_array[4]}/$i;ls -l ${archive_array[4]}/$i"
done

RExec $oracle $NODE1 "/opt/VRTS/bin/dbdst_admin -S \$ORACLE_SID -o definechunk=FAST:256K"
RExec $oracle $NODE1 "/opt/VRTS/bin/dbdst_admin -S \$ORACLE_SID -o definechunk=MEDIUM:512K"
RExec $oracle $NODE1 "/opt/VRTS/bin/dbdst_admin -S \$ORACLE_SID -o definechunk=SLOW:1M"
RExec $oracle $NODE1 "/opt/VRTS/bin/dbdst_admin -S \$ORACLE_SID -o list" "256K,512K,1M"


oLog des "Define Policy and check if files move for ${archive_array[4]}"
RExec $oracle $NODE1 "/opt/VRTSdbed/bin/dbed_update -S \$ORACLE_SID -H \$ORACLE_HOME"
RExec $oracle $NODE1 "/opt/VRTS/bin/fsmap ${archive_array[4]}/*.dbf"

RExec $oracle $NODE1 "/opt/VRTS/bin/dbdst_preset_policy -S \$ORACLE_SID -d ${archive_array[4]} -P FAST=*.dbf"
RExec $oracle $NODE1 "/opt/VRTS/bin/dbdst_preset_policy -S \$ORACLE_SID -l -d ${archive_array[4]}"
RExec $oracle $NODE1 "/opt/VRTS/bin/fsmap ${archive_array[4]}/*.dbf"
if echo "$out"|grep \.dbf|grep -v autotcvol5 > /dev/null 2>&1
then
	oLog error "All of dbf files should be on autotcvol5"
	myexit 1
else
	oLog des "All of the dbf files have move to autotcvol5"
fi

oLog des "move file by dbdst_partition_move and check"
RExec $oracle $NODE1 "/opt/VRTSdbed/bin/dbed_update -S \$ORACLE_SID -H \$ORACLE_HOME"
RExec $oracle $NODE1 "/opt/VRTS/bin/fsmap $dbdata_path/part1.dbf"
if echo "$out"|grep part1|grep -v autotcvol2 > /dev/null 2>&1
then
	type=SLOW
	vol1=autotcvol2
else
	type=FAST
	vol1=autotcvol1
fi

RExec $oracle $NODE1 "/opt/VRTS/bin/dbdst_partition_move -S \$ORACLE_SID -T sales -p sales_yr1 -c $type"
RExec $oracle $NODE1 "/opt/VRTS/bin/fsmap $dbdata_path/part1.dbf"
if echo "$out"|grep part1|grep -v $vol1 > /dev/null 2>&1
then
	oLog error "All file offsets need be located in $vol1"
	myexit 1
else
	oLog des "Attention.All file offsets are located in $vol1"
fi

oLog des "move file by dbdst_tbs_move and check"
RExec $oracle $NODE1 "/opt/VRTSdbed/bin/dbed_update -S \$ORACLE_SID -H \$ORACLE_HOME"
RExec $oracle $NODE1 "/opt/VRTS/bin/fsmap $dbdata_path/part4.dbf"
if echo "$out"|grep part4|grep -v autotcvol2 > /dev/null 2>&1
then
        type=SLOW
        vol1=autotcvol2
else
        type=FAST
        vol1=autotcvol1
fi
RExec $oracle $NODE1 "/opt/VRTS/bin/dbdst_tbs_move -S \$ORACLE_SID -t part4 -c $type"
RExec $oracle $NODE1 "/opt/VRTS/bin/fsmap $dbdata_path/part4.dbf"
if echo "$out"|grep part4|grep -v $vol1 > /dev/null 2>&1
then
	oLog error "All file offsets need be located in $vol1"
	myexit 1
else
	oLog des "Attention.All file offsets are located in $vol1"
fi

oLog des "Making a plan to move files which will happen in 2 minutes"
RExec root $NODE1 "NOEXIT:ntpdate 172.16.8.14"
RExec root $NODE1 "date"
plantime=`date -d '2 minutes' "+%H:%M"`
RExec $oracle $NODE1 "/opt/VRTS/bin/dbdst_admin -S \$ORACLE_SID -o maxclass=8,minclass=2,statinterval=10"
RExec $oracle $NODE1 "/opt/VRTS/bin/dbdst_admin -S \$ORACLE_SID -o sweeptime=$plantime,sweepinterval=1"
RExec $oracle $NODE1 "/opt/VRTS/bin/dbdst_admin -S \$ORACLE_SID -o purgetime=$plantime,purgeinterval=1"
RExec $oracle $NODE1 "/opt/VRTS/bin/dbdst_admin -S \$ORACLE_SID -o list" "Sweep,Purge"

oLog des "Move file by dbdst_file_move with and check "
RExec $oracle $NODE1 "/opt/VRTSdbed/bin/dbed_update -S \$ORACLE_SID -H \$ORACLE_HOME"
RExec $oracle $NODE1 "for i in $dbffile;do /opt/VRTS/bin/fsmap ${archive_array[4]}/\$i;done"

RExec $oracle $NODE1 "/opt/VRTS/bin/dbdst_file_move -S \$ORACLE_SID -o archive -c SLOW:1"
oLog des "Sleep 3 minutes"
sleep 180
RExec root $NODE1 "date"
dbffileno=`echo "$dbffile"|xargs -n1|wc -l`
for seq in {1..10}
do
	oLog des "Checking moving result sequence $seq"
	RExec $oracle $NODE1 "for i in $dbffile;do /opt/VRTS/bin/fsmap ${archive_array[4]}/\$i;done"
	dbffileno1=`echo "$out"|grep autotcvol6|wc -l`
	if [ "$dbffileno1" = "$dbffileno" ]
	then
		break
	fi
	sleep 120
done
if [ "$dbffileno1" = "$dbffileno" ]
then
	oLog des "The orginal dbf files under ${archive_array[4]} which has been changed time has been move to autotcvol6"
else
	oLog error "The orginal dbf files under ${archive_array[4]} which has been changed time should move to autotcvol6"
	myexit 1
fi


RExec $oracle $NODE1 "/opt/VRTS/bin/dbdst_addvol -S \$ORACLE_SID -M /dev/vx/dsk/${dbdata_array[0]}/${dbdata_array[1]} -v autotcvol3:MEDIUM"
RExec $oracle $NODE1 "/opt/VRTS/bin/dbdst_show_fs -S \$ORACLE_SID -m ${dbdata_array[4]}"
dbdatafs0=`echo "$out"|grep SUMMARY:|awk '{print $3}'`
RExec $oracle $NODE1 "/opt/VRTS/bin/dbdst_preset_policy -S \$ORACLE_SID -l -d ${dbdata_array[4]}"
RExec $oracle $NODE1 "/opt/VRTS/bin/dbdst_preset_policy -S \$ORACLE_SID -R -d ${dbdata_array[4]}"
RExec $oracle $NODE1 "/opt/VRTS/bin/dbdst_preset_policy -S \$ORACLE_SID -d ${dbdata_array[4]} -P MEDIUM=*.dbf"
RExec $oracle $NODE1 "/opt/VRTS/bin/dbdst_preset_policy -S \$ORACLE_SID -l -d ${dbdata_array[4]}"
OExec $NODE1 "create tablespace part5 datafile '$dbdata_path/part5.dbf' size 100M;"
sleep 10
RExec $oracle $NODE1 "/opt/VRTS/bin/dbdst_show_fs -S \$ORACLE_SID -m ${dbdata_array[4]}"
dbdatafs1=`echo "$out"|grep SUMMARY:|awk '{print $3}'`
if [ "$dbdatafs1" -gt "$dbdatafs0" ]
then
        oLog des "Attenion,Used size of MEDIUM Class has grown."
else
        oLog error "Used size of MEDIUM Class should grow."
        myexit 1
fi


RExec $oracle $NODE1 "/opt/VRTS/bin/dbdst_addvol -S \$ORACLE_SID -M /dev/vx/dsk/${dbdata_array[0]}/${dbdata_array[1]} -v autotcvol4:MEDIUM"
RExec $oracle $NODE1 "/opt/VRTS/bin/dbdst_show_fs -S \$ORACLE_SID -m ${dbdata_array[4]}"
RExec $oracle $NODE1 "/opt/VRTS/bin/dbdst_preset_policy -S \$ORACLE_SID -R -d ${dbdata_array[4]}"
RExec $oracle $NODE1 "/opt/VRTS/bin/dbdst_preset_policy -S \$ORACLE_SID -d ${dbdata_array[4]} -P MEDIUM=*.dbf"
RExec $oracle $NODE1 "/opt/VRTS/bin/dbdst_preset_policy -S \$ORACLE_SID -l -d ${dbdata_array[4]}"
OExec $NODE1 "create tablespace part6 datafile '$dbdata_path/part6.dbf' size 100M;"
RExec $oracle $NODE1 "/opt/VRTS/bin/dbdst_show_fs -S \$ORACLE_SID -m ${dbdata_array[4]}"
for i in `seq 20`
do
	RExec $oracle $NODE1 "NOEXIT:/opt/VRTS/bin/dbdst_rmvol -S \$ORACLE_SID -M /dev/vx/dsk/${dbdata_array[0]}/${dbdata_array[1]} -v autotcvol4"
	[ "$result" = Passed ] && break
done
RExec $oracle $NODE1 "/opt/VRTS/bin/dbdst_show_fs -S \$ORACLE_SID -m ${dbdata_array[4]}" "" "autotcvol4"


RExec $oracle $NODE1 "/opt/VRTS/bin/dbdst_show_fs -S \$ORACLE_SID -m ${dbdata_array[4]}"
RExec $oracle $NODE1 "/opt/VRTS/bin/dbdst_show_fs -S \$ORACLE_SID -m ${archive_array[4]}"
RExec $oracle $NODE1 "/opt/VRTS/bin/dbdst_admin -S \$ORACLE_SID -o list"
RExec $oracle $NODE1 "/opt/VRTS/bin/dbdst_report -S \$ORACLE_SID -o audit"
RExec $oracle $NODE1 "/opt/VRTS/bin/dbdst_report -S \$ORACLE_SID -o policy"
}

dbdstRemoveVset(){
local dg vol
dg=$1
vol=$2
RExec root $NODE1 "vxvset -g $dg list $vol"
for i in `echo "$out"|grep -v INDEX|awk '{print $1}'|tac`
do
	RExec root $NODE1 "vxvset -g $dg rmvol $vol $i"
done
RExec root $NODE1 "vxedit -g $dg rename $vol-b4vset $vol"
}

dbdstCleanEnv(){
local table tables i flag
flag=0
OExec $NODE1 "select table_name from dba_tables where table_name='SALES';"
echo "$out"|grep -i sales > /dev/null 2>&1 && OExec $NODE1 'drop table sales;'
OExec $NODE1 'select name from v$tablespace;'
tables=`echo "$out"|grep -P "^PART[0-9]+"|tr [A-Z] [a-z]`
for table in $tables
do
	OExec $NODE1 "drop tablespace $table including contents and datafiles;"
done
RExec root $NODE1 "/opt/VRTS/bin/fsppadm unassign /dbdata"
RExec root $NODE1 "/opt/VRTS/bin/fsppadm unassign /archive"
RExec root $NODE1 "vxprint -g ${dbdata_array[0]}|awk '\$2==\"${dbdata_array[1]}\" {print}'"
if echo "$out"|grep ^vt > /dev/null 2>&1
then
	flag=1
	RExec $oracle $NODE1 "/opt/VRTS/bin/dbdst_show_fs -S \$ORACLE_SID -m ${dbdata_array[4]}"
	for i in `echo "$out"|grep -v ^${dbdata_array[1]}|grep autotc|awk '{print $1}'`
	do
		RExec root $NODE1 "/opt/VRTS/bin/fsvoladm remove ${dbdata_array[4]} $i"
	done
fi
RExec root $NODE1 "vxprint -g ${archive_array[0]}|awk '\$2==\"${archive_array[1]}\" {print}'"
if echo "$out"|grep ^vt > /dev/null 2>&1
then
	flag=2
        RExec $oracle $NODE1 "/opt/VRTS/bin/dbdst_show_fs -S \$ORACLE_SID -m ${archive_array[4]}"
        for i in `echo "$out"|grep -v ^${archive_array[1]}|grep autotc|awk '{print $1}'`
        do
                RExec root $NODE1 "/opt/VRTS/bin/fsvoladm remove ${archive_array[4]} $i"
        done
fi
if [ $flag -ne 0 ]
then
	stopGroupAny $NODE1 $oracle_group
	[ $flag = 1 ] && dbdstRemoveVset ${dbdata_array[0]} ${dbdata_array[1]}
	[ $flag = 2 ] && dbdstRemoveVset ${dbdata_array[0]} ${dbdata_array[1]} && dbdstRemoveVset ${archive_array[0]} ${archive_array[1]}
fi
rmVolumeBeginWithStringFromDg $NODE1 ${dbdata_array[0]} autotcvol
rmVolumeBeginWithStringFromDg $NODE1 ${archive_array[0]} autotcvol
rmFreeDiskFromDg $NODE1
startGroupAny $NODE1 $oracle_group
}
