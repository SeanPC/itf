dbedFlashsnap(){
local dbed_config dbed_sid
dbed_config=autotc
dbed_sid=clone
#add mirror for dbdata and archive volume
snapshotAddmir $NODE1 ${dbdata_array[0]} ${dbdata_array[1]} ${dbdata_array[2]}
snapshotAddmir $NODE1 ${archive_array[0]} ${archive_array[1]} ${archive_array[2]}

oLog "des" "Clone database and check by using Flashsnap method"
RExec $oracle $NODE1 "NOEXIT:/opt/VRTSdbed/bin/dbed_update -S \$ORACLE_SID -H \$ORACLE_HOME"
if [ $? -eq 1 ]
then
        oLog "des" "Waring: Trying to fix it through workaroud"
        RExec root $NODE1 'NOEXIT:rm -f /var/vx/vxdba/rep_loc;/opt/VRTSdbed/bin/vxdbd stop;rm -rf /var/vx/vxdba/auth /opt/VRTSdbed/at-broker /var/VRTSat /var/VRTSat_lhc;echo "AUTHENTICATION=no" > /etc/vx/vxdbed/admin.properties;/opt/VRTSdbed/bin/vxdbd start'
        sleep 20
        RExec $oracle $NODE1 "/opt/VRTSdbed/bin/dbed_update -S \$ORACLE_SID -H \$ORACLE_HOME"
fi
RExec $oracle $NODE1 "/opt/VRTSdbed/bin/vxsfadm -s flashsnap -a oracle -o list"
if echo "$out"|grep autotc > /dev/null 2>&1
then
        oLog des "Tring to clean exsiting configuration."
        RExec $oracle $NODE1 "NOEXIT:/opt/VRTS/bin/vxsfadm -s flashsnap -o umount -a oracle --oracle_sid \$ORACLE_SID --oracle_home \$ORACLE_HOME --flashsnap_name $dbed_config --clone_name $dbed_sid"
        RExec $oracle $NODE1 "/opt/VRTSdbed/bin/vxsfadm -s flashsnap -a oracle -o destroy --name $dbed_config"
fi
RExec $oracle $NODE1 "rm -f $dbed_config;/opt/VRTS/bin/vxsfadm -s flashsnap -o setdefaults -a oracle --oracle_sid \$ORACLE_SID --oracle_home \$ORACLE_HOME -c $dbed_config"
RExec $oracle $NODE1 "cat $dbed_config"
RExec $oracle $NODE1 "/opt/VRTS/bin/vxsfadm -s flashsnap -o validate -a oracle --oracle_sid \$ORACLE_SID --oracle_home \$ORACLE_HOME --flashsnap_name $dbed_config --app_mode online"
RExec $oracle $NODE1 "/opt/VRTS/bin/vxsfadm -s flashsnap -o mount -a oracle --oracle_sid \$ORACLE_SID --oracle_home \$ORACLE_HOME --flashsnap_name $dbed_config"
RExec $oracle $NODE1 "/opt/VRTS/bin/vxsfadm -s flashsnap -o clone -a oracle --oracle_sid \$ORACLE_SID --oracle_home \$ORACLE_HOME --flashsnap_name $dbed_config --clone_name $dbed_sid"
RExec $oracle $NODE1 '/opt/VRTSdbed/bin/vxsfadm -s flashsnap -a oracle -o list'
RExec $oracle $NODE1 "$cmd2"
RExec $oracle $NODE1 "ps -ef|grep smon"
checkOracleByInst $dbed_sid
RExec $oracle $NODE1 "/opt/VRTS/bin/vxsfadm -s flashsnap -o umount -a oracle --oracle_sid \$ORACLE_SID --oracle_home \$ORACLE_HOME --flashsnap_name $dbed_config --clone_name $dbed_sid"
RExec $oracle $NODE1 "ps -ef|grep smon"
RExec $oracle $NODE1 "$cmd2"
RExec $oracle $NODE1 '/opt/VRTSdbed/bin/vxsfadm -s flashsnap -a oracle -o list'
#RExec $oracle $NODE1 "/opt/VRTSdbed/bin/vxsfadm -s flashsnap -a oracle -o list|grep flashsnap|awk '{print \$2}'|xargs -n1 /opt/VRTSdbed/bin/vxsfadm -s flashsnap -a oracle -o destroy --name"
RExec $oracle $NODE1 "/opt/VRTSdbed/bin/vxsfadm -s flashsnap -a oracle -o destroy --name $dbed_config"
RExec $oracle $NODE1 '/opt/VRTSdbed/bin/vxsfadm -s flashsnap -a oracle -o list'
sleep 5
snapshotRMmir $NODE1 ${dbdata_array[0]} ${dbdata_array[1]}
snapshotRMmir $NODE1 ${archive_array[0]} ${archive_array[1]}
}
AddSPS(){
local cache newvol cacheobj dg vol dgdetail
dg=$1
vol=$2
cache=cachetc
newvol=oracle
cacheobj=cacheobjtc
RExec root $NODE1 "vxprint -g $dg"
dgdetail="$out"
if echo "$dgdetail"|grep $newvol > /dev/null 2>&1
then
        oLog des "Tring to clean exsiting configuration."
        RExec root $NODE1 "vxedit -g $dg -rf rm $newvol"
fi
if echo "$dgdetail"|grep $cache > /dev/null 2>&1
then
        RExec root $NODE1 "NOEXIT:vxcache -g $dg stop $cacheobj;vxedit -g $dg -rf rm $cacheobj;vxsnap -g $dg unprepare $vol"
fi
RExec root $NODE1 "vxassist -g $dg make $cache 2g"
RExec root $NODE1 "vxmake -g $dg cache $cacheobj cachevolname=$cache"
RExec root $NODE1 "vxcache -g $dg start $cacheobj"
RExec root $NODE1 "vxprint -g $dg" "$cacheobj"
RExec root $NODE1 "vxsnap -g $dg prepare $vol"
RExec root $NODE1 "vxsnap -g $dg make source=$vol/newvol=$newvol/cache=$cacheobj"
RExec root $NODE1 "vxprint -g $dg"
}
RMSPS(){
local cache newvol cacheobj dg vol
dg=$1
vol=$2
cache=cachetc
newvol=oracle
cacheobj=cacheobjtc
RExec root $NODE1 "vxprint -g $dg"
RExec root $NODE1 "vxedit -g $dg -rf rm $newvol"
RExec root $NODE1 "vxcache -g $dg stop $cacheobj"
RExec root $NODE1 "vxedit -g $dg -rf rm $cacheobj"
RExec root $NODE1 "vxsnap -g $dg unprepare $vol"
RExec root $NODE1 "vxprint -g $dg"
}
dbedSPS(){
local dbed_config dbed_sid i j k
dbed_config=autotc
RExec $oracle $NODE1 "/opt/VRTS/bin/vxsfadm -s sos -a oracle -o list --oracle_sid \$ORACLE_SID --oracle_home \$ORACLE_HOME"
echo "$out"|grep ^sos|grep $dbed_config|while read i j k
do
        oLog des "Tring to clean exsiting configuration."
        [ "$k" = clone ] && RExec $oracle $NODE1 "/opt/VRTS/bin/vxsfadm -s sos -a oracle -o umount --oracle_sid \$ORACLE_SID --oracle_home \$ORACLE_HOME --sos_name $j"
        RExec $oracle $NODE1 "/opt/VRTS/bin/vxsfadm -s sos -a oracle -o destroy --oracle_sid \$ORACLE_SID --oracle_home \$ORACLE_HOME --sos_name $j"
done
RExec $oracle $NODE1 "rm -rf $dbed_config;/opt/VRTS/bin/vxsfadm -s sos -a oracle -o setdefaults --oracle_sid \$ORACLE_SID --oracle_home \$ORACLE_HOME --sos_name $dbed_config -c $dbed_config"
RExec $oracle $NODE1 "cat $dbed_config"
RExec $oracle $NODE1 "/opt/VRTS/bin/vxsfadm -s sos -a oracle -o validate --oracle_sid \$ORACLE_SID --oracle_home \$ORACLE_HOME --sos_name $dbed_config -c $dbed_config"
RExec $oracle $NODE1 "/opt/VRTS/bin/vxsfadm -s sos -a oracle -o snap --oracle_sid \$ORACLE_SID --oracle_home \$ORACLE_HOME --sos_name $dbed_config -c $dbed_config"
RExec $oracle $NODE1 "/opt/VRTS/bin/vxsfadm -s sos -a oracle -o clone --oracle_sid \$ORACLE_SID --oracle_home \$ORACLE_HOME --sos_name $dbed_config -c $dbed_config"
dbed_sid=`echo "$out"|grep -oP "\w+(?= is open)"`
RExec $oracle $NODE1 "$cmd2"
RExec $oracle $NODE1 "ps -ef|grep smon"
checkOracleByInst $dbed_sid tmp
RExec $oracle $NODE1 "/opt/VRTS/bin/vxsfadm -s sos -a oracle -o list --oracle_sid \$ORACLE_SID --oracle_home \$ORACLE_HOME"
RExec $oracle $NODE1 "/opt/VRTS/bin/vxsfadm -s sos -a oracle -o umount --oracle_sid \$ORACLE_SID --oracle_home \$ORACLE_HOME --sos_name $dbed_config"
RExec $oracle $NODE1 "$cmd2"
RExec $oracle $NODE1 "ps -ef|grep smon"
RExec $oracle $NODE1 "/opt/VRTS/bin/vxsfadm -s sos -a oracle -o destroy --oracle_sid \$ORACLE_SID --oracle_home \$ORACLE_HOME --sos_name $dbed_config"
RExec $oracle $NODE1 "/opt/VRTS/bin/vxsfadm -s sos -a oracle -o list --oracle_sid \$ORACLE_SID --oracle_home \$ORACLE_HOME"
}

dbedCheckPoint(){
local ckpname ckpname0 dbed_sid opt
ckpname=autotc
dbed_sid=clone
RExec $oracle $NODE1 "/opt/VRTSdbed/bin/vxsfadm -s checkpoint -a oracle -o list"
if echo "$out"|grep autotc > /dev/null 2>&1
then
	oLog des "Tring to clean exsiting configuration."
	RExec $oracle $NODE1 "NOEXIT:/opt/VRTSdbed/bin/vxsfadm -s checkpoint -o umount -a oracle --oracle_sid=\$ORACLE_SID --oracle_home=\$ORACLE_HOME --checkpoint_name=$ckpname --clone_path=/tmp/$ckpname --clone_name=$dbed_sid"
	RExec $oracle $NODE1 "/opt/VRTSdbed/bin/vxsfadm -s checkpoint -o delete -a oracle --oracle_sid=\$ORACLE_SID --oracle_home=\$ORACLE_HOME --checkpoint_name=$ckpname"
fi
RExec $oracle $NODE1 "/opt/VRTSdbed/bin/vxsfadm -s checkpoint -o create -a oracle --oracle_sid=\$ORACLE_SID --oracle_home=\$ORACLE_HOME --checkpoint_name=$ckpname"
for opt in mount mountrw
do
	RExec $oracle $NODE1 "/opt/VRTSdbed/bin/vxsfadm -s checkpoint -o $opt -a oracle --oracle_sid=\$ORACLE_SID --oracle_home=\$ORACLE_HOME --checkpoint_name=$ckpname --mount_path=/tmp/$ckpname"
	RExec $oracle $NODE1 "$cmd2"
	ckpname0=`echo "$out"|grep /tmp/$ckpname|grep -oP "(?<=${dbdata_array[1]}:)\w+"`
	RExec $oracle $NODE1 "/opt/VRTSdbed/bin/vxsfadm -s checkpoint -o umount -a oracle --oracle_sid=\$ORACLE_SID --oracle_home=\$ORACLE_HOME --checkpoint_name=$ckpname0"
	RExec $oracle $NODE1 "$cmd2"
done
RExec $oracle $NODE1 "/opt/VRTSdbed/bin/vxsfadm -s checkpoint -o delete -a oracle --oracle_sid=\$ORACLE_SID --oracle_home=\$ORACLE_HOME --checkpoint_name=$ckpname0"
RExec $oracle $NODE1 "/opt/VRTSdbed/bin/vxsfadm -s checkpoint -o delete -a oracle --oracle_sid=\$ORACLE_SID --oracle_home=\$ORACLE_HOME --checkpoint_name=$ckpname"
RExec $oracle $NODE1 "/opt/VRTSdbed/bin/vxsfadm -s checkpoint -o clone -a oracle --oracle_sid=\$ORACLE_SID --oracle_home=\$ORACLE_HOME --checkpoint_name=$ckpname --clone_path=/tmp/$ckpname --clone_name=$dbed_sid"
RExec $oracle $NODE1 "/opt/VRTSdbed/bin/vxsfadm -s checkpoint -a oracle -o list"
RExec $oracle $NODE1 "ps -ef|grep smon"
RExec $oracle $NODE1 "$cmd2"
ckpname0=`echo "$out"|grep /tmp/$ckpname|grep -oP "(?<=${dbdata_array[1]}:)\w+"`
checkOracleByInst $dbed_sid
RExec $oracle $NODE1 "/opt/VRTSdbed/bin/vxsfadm -s checkpoint -o umount -a oracle --oracle_sid=\$ORACLE_SID --oracle_home=\$ORACLE_HOME --checkpoint_name=$ckpname --clone_path=/tmp/$ckpname --clone_name=$dbed_sid"
RExec $oracle $NODE1 "$cmd2"
RExec $oracle $NODE1 "ps -ef|grep smon"
RExec $oracle $NODE1 "/opt/VRTSdbed/bin/vxsfadm -s checkpoint -a oracle -o list"
RExec $oracle $NODE1 "/opt/VRTSdbed/bin/vxsfadm -s checkpoint -o delete -a oracle --oracle_sid=\$ORACLE_SID --oracle_home=\$ORACLE_HOME --checkpoint_name=$ckpname0"
RExec $oracle $NODE1 "/opt/VRTSdbed/bin/vxsfadm -s checkpoint -o delete -a oracle --oracle_sid=\$ORACLE_SID --oracle_home=\$ORACLE_HOME --checkpoint_name=$ckpname"
RExec $oracle $NODE1 "/opt/VRTSdbed/bin/vxsfadm -s checkpoint -a oracle -o list"
}
dbedFileSnap(){
local filesnap dbed_sid
filesnap=autotc
dbed_sid=clone
RExec $oracle $NODE1 "/opt/VRTSdbed/bin/vxsfadm -s filesnap -a oracle -o list --oracle_sid \$ORACLE_SID"
if echo "$out"|grep autotc > /dev/null 2>&1
then
	RExec $oracle $NODE1 "NOEXIT:/opt/VRTSdbed/bin/vxsfadm -s filesnap -a oracle --oracle_sid \$ORACLE_SID -oracle_home \$ORACLE_HOME --filesnap_name $filesnap --clone_name $dbed_sid -o destroyclone"
	RExec $oracle $NODE1 "/opt/VRTSdbed/bin/vxsfadm -s filesnap -a oracle --oracle_sid \$ORACLE_SID -oracle_home \$ORACLE_HOME --filesnap_name $filesnap -o destroysnap"	
fi
RExec $oracle $NODE1 "rm -f $filesnap;/opt/VRTSdbed/bin/vxsfadm -s filesnap -a oracle --oracle_sid \$ORACLE_SID -oracle_home \$ORACLE_HOME --filesnap_name $filesnap -c $filesnap -o setdefaults"
RExec $oracle $NODE1 "cat $filesnap"
RExec $oracle $NODE1 "/opt/VRTSdbed/bin/vxsfadm -s filesnap -a oracle --oracle_sid \$ORACLE_SID -oracle_home \$ORACLE_HOME --filesnap_name $filesnap -o snap"
RExec $oracle $NODE1 "/opt/VRTSdbed/bin/vxsfadm -s filesnap -a oracle --oracle_sid \$ORACLE_SID -oracle_home \$ORACLE_HOME --filesnap_name $filesnap --clone_name $dbed_sid -o clone"
RExec $oracle $NODE1 "/opt/VRTSdbed/bin/vxsfadm -s filesnap -a oracle -o list --oracle_sid \$ORACLE_SID"
RExec $oracle $NODE1 "ps -ef|grep smon"
checkOracleByInst $dbed_sid tmp
RExec $oracle $NODE1 "ps -ef|grep smon"
RExec $oracle $NODE1 "/opt/VRTSdbed/bin/vxsfadm -s filesnap -a oracle --oracle_sid \$ORACLE_SID -oracle_home \$ORACLE_HOME --filesnap_name $filesnap --clone_name $dbed_sid -o destroyclone"
RExec $oracle $NODE1 "/opt/VRTSdbed/bin/vxsfadm -s filesnap -a oracle -o list --oracle_sid \$ORACLE_SID"
RExec $oracle $NODE1 "/opt/VRTSdbed/bin/vxsfadm -s filesnap -a oracle --oracle_sid \$ORACLE_SID -oracle_home \$ORACLE_HOME --filesnap_name $filesnap -o destroysnap"
RExec $oracle $NODE1 "/opt/VRTSdbed/bin/vxsfadm -s filesnap -a oracle -o list --oracle_sid \$ORACLE_SID"
}
