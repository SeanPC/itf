mkVxfs(){
#DES:create vxfs on volume
node=$1
dg=$2
vol=$3
if [ -z "$type" ]
then
        oLog error "Failed to get OS Type"
        myexit 1
fi
if [ $type = L ]
then
        opt1="-t"
elif  [ $type = A ]
then
        opt1="-V"
elif  [ $type = S ]
then
        opt1="-F"
fi
RExec root $node "mkfs $opt1 vxfs /dev/vx/rdsk/$dg/$vol"
}
mountVxfs(){
#DES:mount vxfs filesystem
local node dg vol mp opt opt1
node=$1
dg=$2
vol=$3
mp=$4
opt=$5
if [ -z "$type" ]
then
        oLog error "Failed to get OS Type"
        myexit 1
fi
if [ $type = L ]
then
        opt1="-t"
elif  [ $type = A ]
then
        opt1="-V"
elif  [ $type = S ]
then
        opt1="-F"
fi
RExec root $node "mkdir -p $mp && mount $opt $opt1 vxfs /dev/vx/dsk/$dg/$vol $mp"
RExec root $node "$cmd2"
}
umountVxfs(){
#DES:umount Vxfs
local node keepmp umount_mp umount_cmd
node=$1
keepmp=$2
oLog des "umount vxfs on node $node"
RExec root $node "$cmd2"
if [ -z "$keepmp" ]
then
	umount_mp=`echo "$out"|grep "autotc"|awk '{print $NF}'`
else
	keepmp=`echo "$keepmp"|sed -r "s/,/\$|/g;s/$/\$/"`
	umount_mp=`echo "$out"|grep "autotc"|awk '{print $NF}'|grep -vP "$keepmp"`
fi
[ -z "$umount_mp" ] && return 0
umount_cmd=`echo "$umount_mp"|xargs -n 10000|sed -r "s/[^ ]+/umount &;/g;s/; /;/g"`
echo "$umount_cmd"|grep umount > /dev/null 2>&1 && RExec root $node "NOEXIT:$umount_cmd"
}
fsStressStart(){
#DES:Start the IO action.
local node dir
node=$1
dir=$2
oLog des "Staring io action to $dir on $node"
copyFileToRemote $BASE/etc/io_activity.pl $node
RExec root $node "/tmp/tmpfile.$PID -d $dir"
fsstresspid=`echo "$out"|grep -oP "^[0-9]+"`
}
fsStressStop(){
#DES:Stop the IO action on $node.Will kill $fsstresspid if pids is empty
local node pids
node=$1
pids=$2
oLog des "Stopping io action"
[ -z "$fsstresspid" ] && return 0
[ -n "$pids" ] && fsstresspid="$pids"
RExec root $node "NOERROR:kill -9 $fsstresspid"
sleep 2
}
checkFsStressByMountpoint(){
#DES:Check the file system stress by mountpoint.
local node mp vol i n
node=$1
mp=$2
n=0
RExec root $node "$cmd2"
[ $type = A ] && vol=`echo "$out"|awk '$7=="'$mp'"{print $1}'|awk -F/ '{print $6}'`|| vol=`echo "$out"|awk '$6=="'$mp'"{print $1}'|awk -F/ '{print $6}'`
if [ -z "$vol" ]
then
        oLog error "The mountpoint $mp doesn't exist"
        myexit 1
fi
out=`getDgVolumeDmpnodeMap $node` || exit 1
dmpnodes=`echo "$out"|grep ":$vol:"|awk -F: '{print $3}'|sed -r "s/ /|/g"`
for i in `seq 10`
do
        RExec root $node "/opt/VRTS/bin/vxdmpadm iostat reset"
        sleep 10
        RExec root $node "/opt/VRTS/bin/vxdmpadm -uk iostat show groupby=dmpnode|awk '\$1 ~ /$dmpnodes/ {print}'"
        if echo "$out"|awk '{print $4,$5}'|grep -vP " 0k\s+0k" >/dev/null 2>&1
        then
		break
	else
                n=$[$n+1]
        fi
        sleep 10
done
[ $n -eq 10 ] && oLog error "NO IO found on the mountpiont $mp" && myexit 1
}
fsStressStartWithThrash(){
local node dir num dn n i
node=$1
dir=$2
num=$3
i=1
[ -z "$num" ] && num=1
dn=`echo "$dir"|awk -F/ '{print $3}'`
oLog des "Staring io action on $dir"
for n in `seq $num`
do
        RExec root $node "dd if=/dev/zero of=$dir/worker_${node}_$i bs=512 seek=2831155 count=1"
        RExec root $node "nohup /tmp/tmpfile.$PID -l /tmp/$tc.thrash.$node.$dn.$i.log -f 1 -t 864000 -2sxXz $dir/worker_${node}_$i > /dev/null 2>&1 &"
        i=$[$i+1]
done
}
fsStressStopWithThrash(){
local node pid
node=$1
oLog des "Stopping io action"
RExec root $node "ps -ef|grep thrash"
pid=`echo "$out"|grep -v " thrash"|awk '{print $2}'|xargs -n100`
[ -n "$pid" ] && RExec root $node "kill -9 $pid"
}
cfsMount(){
#DES:mount cfs by using cfsmntadm
local node node0 dg vol mp group opt
node=$1
dg=$2
vol=$3
mp=$4
group=$5
opt=$6
[ "$group" = "random" ] && group=""
[ -z "$opt" ] && opt="all=rw"
for node0 in $NODES
do
        RExec root $node0 "mkdir -p $mp"
done
RExec root $node "/opt/VRTS/bin/cfsmntadm add $dg $vol $mp $group $opt"
RExec root $node "/opt/VRTS/bin/cfsmount $mp && /opt/VRTS/bin/cfsmntadm display $mp"
}
cfsUmount(){
#DES:umount cfs by using cfsmntadm
local node mp
node=$1
mp=$2
RExec root $node "/opt/VRTS/bin/cfsmntadm display $mp"
RExec root $node "/opt/VRTS/bin/cfsmntadm delete -f $mp"
}
getCfsNodeRole(){
#DES:get the primary node and none primary node,output will be nodes seprated by space
local node mp pnode npnode
node=$1
mp=$2
RExec root $node "/opt/VRTS/bin/fsclustadm -v showprimary $mp"
pnode=$out
npnode=`echo "$NODES"|sed "s/$pnode//"`
echo $pnode $npnode
}
