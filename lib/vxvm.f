makeVolBySize(){
#DES:Make volume with specified size,size should follow unit(opt should be fs or raw,layout could be stripe or mirror,layoutopt example:"ncol=5")
local node vol dg size opt layout layoutopt
node=$1
dg=$2
vol=$3
size=$4
opt=$5
layout=$6
layoutopt=$7
oLog des "Making $vol with size=$size in $dg"
if [ -z "$type" ]
then
        oLog error "Failed to get OS Type"
        myexit 1
fi
RExec root $node "for i in \`vxprint -g $dg|grep ^v|grep $vol|awk '{print \$2}'\`;do vxedit -g $dg -rf rm \$i;done"
if [ -z "$layout" ]
then
	RExec root $node "vxassist -g $dg make $vol $size"
else 
	RExec root $node "vxassist -g $dg make $vol $size layout=$layout $layoutopt "
fi
if [ "$opt" = fs ]
then
	if [ $type = L ]
	then
		RExec root $node "/opt/VRTS/bin/mkfs -t vxfs /dev/vx/rdsk/$dg/$vol"
	elif [ $type = A ]
	then
		RExec root $node "/opt/VRTS/bin/mkfs -V vxfs /dev/vx/rdsk/$dg/$vol"
	elif [ $type = S ]
	then
		RExec root $node "/opt/VRTS/bin/mkfs -F vxfs /dev/vx/rdsk/$dg/$vol"
	fi
fi
}
makeLocalDgBySize(){
#DES:Make dg with specified size using local disk,size can only be a number counting by uint MB
local node dg size disk opt
node=$1
dg=$2
size=$3
[ -z "$node" -o -z "$dg" -o -z "$size" ] && myexit 1 
if [[ "$size" =~ ^[0-9]+$ ]]
then
        :
else
        oLog error "syntax error,size can only be a number counting by uint MB"
        myexit 1
fi
oLog des "Making dg \"$dg\" with maxsize=$size"
RExec root $node "vxdg list"
if echo "$out"|grep -P "^$dg " > /dev/null 2>&1
then
        RExec root $node "vxdg destroy $dg"
fi
disk=`getDiskBySizeWithPath $node $size local` || exit 201
Exec root $node "vxdg init $dg $disk"
}

makeDgBySize(){
#DES:Make dg with specified size using shared disk(opt could be empty or use define),size can only be a number counting by uint MB
local node dg size disk opt
node=$1
dg=$2
size=$3
opt=$4
[ -z "$node" -o -z "$dg" -o -z "$size" ] && myexit 1
if [[ "$size" =~ ^[0-9]+$ ]]
then
        :
else
        oLog error "syntax error,size can only be a number counting by uint MB"
        myexit 1
fi
oLog des "Making dg \"$dg\" with maxsize=$size"
RExec root $node "vxdg list"
if echo "$out"|grep -P "^$dg " > /dev/null 2>&1
then
        RExec root $node "vxdg destroy $dg"
fi
disk=`getDiskBySizeWithPath $node $size share` || exit 201
if [ -z "$opt" ]
then 
	RExec root $node "vxdg init $dg $disk"
else
	RExec root $node "vxdg $opt init $dg $disk"	
fi
}
makeDgBySizeAndStripe(){
#DES:Make dg with specified size and stripe option.(ncol could be number,opt could be empty or "-s")
local node dg size disk ncol opt
node=$1
dg=$2
size=$3
ncol=$4
opt=$5
size=`echo "$size*2"|bc|cut -d . -f 1`
[ -z "$node" -o -z "$dg" -o -z "$size" -o -z "$ncol" ] && myexit 1
if [[ "$size" =~ ^[0-9]+$ ]]
then
        :
else
        oLog error "syntax error,size can only be a number counting by uint MB"
        myexit 1
fi
oLog des "Making dg \"$dg\" with maxsize=$size and stripe ncol=$ncol"
RExec root $node "vxdg list"
if echo "$out"|grep -P "^$dg " > /dev/null 2>&1
then
        RExec root $node "vxdg destroy $dg"
fi
for i in `seq 10`
do
        disk+=`getDiskBySizeWithPath $node $size share` || exit 201
        [ `echo "$disk"|awk '{print NF}'` -ge $ncol ] && break
done
if [ "$opt" = -s ]
then
        RExec root $node "vxdg -s init $dg $disk"
else
        RExec root $node "vxdg init $dg $disk"
fi
}

makeDgBySizeAndMirror(){
#DES:Make dg with specified size and mirror option.(nmirror could be number,opt could be empty or "-s")
local node dg size disk nmirror opt
node=$1
dg=$2
size=$3
nmirror=$4
opt=$5
size=`echo "$size*3"|bc|cut -d . -f 1`
[ -z "$node" -o -z "$dg" -o -z "$size" -o -z "$nmirror" ] && myexit 1
if [[ "$size" =~ ^[0-9]+$ ]]
then
        :
else
        oLog error "syntax error,size can only be a number counting by uint MB"
        myexit 1
fi
oLog des "Making dg \"$dg\" with maxsize=$size and stripe nmirror=$nmirror"
RExec root $node "vxdg list"
if echo "$out"|grep -P "^$dg " > /dev/null 2>&1
then
        RExec root $node "vxdg destroy $dg"
fi
for i in `seq 10`
do
	disk+=`getDiskBySizeWithPath $node $size share` || exit 201
	[ `echo "$disk"|awk '{print NF}'` -ge $nmirror ] && break
done
if [ "$opt" = -s ]
then
        RExec root $node "vxdg -s init $dg $disk"
else
        RExec root $node "vxdg init $dg $disk"
fi
}

getVolumeDataByMount(){
#DES:Get vol properties by mount point,output will be a string,size unit is MB
local node mnt path dg name size fs
node=$1
mnt=$2
oLog "des" "Getting volume dg,name,size,filesystem,mountpoint by mountpoint $mnt"
[ -z "$mnt" ] && oLog "error" "Failed to get MountPoint,can not go on" && myexit 1
RExec root $node "$cmd2"
out=`echo "$out"|grep $mnt$`
path=`echo "$out"|cut -d ' ' -f 1`
dg=`echo "$out"|cut -d ' ' -f 1|awk -F "/" '{print $(NF-1)}'`
[ -z "$dg" ] && oLog "error" "Failed to get dg name" && myexit 1
name=`echo "$out"|cut -d ' ' -f 1|awk -F "/" '{print $NF}'`
[ -z "$name" ] && oLog "error" "Failed to get volunme name" && myexit 1
size=`echo "$out"|awk '{print $2}'`
[ -z "$size" ] && oLog "error" "Failed to get volunme size" && myexit 1
#covert unit to M and just export the number
[ $type = A ] && size=${size}g 
if [[ "$size" =~ g|G ]]
then
	size=`echo "$size"|sed -r "s/g|G/\*1024+100/"|bc|cut -d . -f 1`
elif [[ "$size" =~ t|T ]]
then
	size=`echo "$size"|sed -r "s/g|G/\*1024\*1024+100/"|bc|cut -d . -f 1`
fi
fs=`RExec root $node "/opt/VRTS/bin/fstyp $path" vxfs;echo $out`
echo "$dg $name $size $fs $mnt $path"
}

getDiskSizeDgByVxlist(){
#DES:List disk by vxlist for elder SF version
local a b c b0 node
node=$1
RExec root $node "/opt/VRTSsfmh/adm/dclisetup.sh"
RExec root $node "/opt/VRTS/bin/vxlist disk"
echo "$out"|grep -v SIZE|awk '{print $2 " " $5 " " $4}'|while read a b c
do
        if [[ $b =~ [0-9](m|M|g|G|t|T)$ ]]
        then
                b0=`echo $b|sed -r "s/m|M//;s/g|G/*1024/;s/t|T/*1024*1024/"|bc|cut -d . -f 1`
                echo "$a $b0 $c"
        fi
done
}

getDiskSizeDgByVxdisk(){
#DES:List disk by vxdisk -o size
local node
node=$1
RExec root $node 'vxdisk -o alldgs,size list'
echo "$out"|awk ' $2 ~ /[0-9]+/ {print}'
}

getDiskDetail(){
local disk disk_detail n node
node=$1
disk=$2
RExec root $node "vxdisk list $disk"
disk_detail=`echo "$out"|xargs -n 10000000000|sed -r "s/Device:/\nDevice:/g;"|grep -oP "(?<=Device: )\w+|(?<=udid: )[^ ]+|(?<=numpaths: )[0-9]+"`
n=`echo "$disk_detail"|wc -l`
if [ `echo "$n%3"|bc` -ne 0 ]
then
	oLog error "Failed in getting disk detail"
	myexit 1
fi
echo "$disk_detail"|xargs -n3
}

getDisk(){
#DES:Get available disks(opt could be local or share)
local node node1 i encl exp_encl exp_cdsdisk exp_thin adisk adisk0 adisk1 opt disk_detail_node disk_detail_other disk_detail_node_disk
oLog "des" "Getting avaiable disks"
node=$1
opt=$2
if [ "$opt" = local -o "$opt" = share ] 
then
	:
else
	oLog error "Invaild var opt \"$opt\" in getDISK"
	myexit 201
fi
for node1 in $NODES
do
	RExec root $node1 "vxddladm set namingscheme=ebn persistence=yes"
done
RExec root $node 'vxdmpadm listenclosure'
encl=`echo "$out"|grep -viP "ENCLR_NAME|===|disk|scsi"|awk '{print $1}'`
if [ -z "$encl" ]
then
	oLog error "Failed to get enclosure name"
	myexit 201
else
	exp_encl=`echo "$encl"|xargs -n100|sed -r "s/ /|^/g;s/^/^/"`
	echo "exp_encl='$exp_encl'" >> $logs/define
fi
#if need init invalid disk
RExec root $node 'vxdisk scandisks;vxdisk list'
disks=`echo "$out"|grep -P "$exp_encl"|grep -i online|grep -i invalid|awk '{print $1}'|grep -vP "^\s*$"|xargs -n10000`
if [ -n "$disks" ]
then
	RExec root $node "NOEXIT:for i in $disks;do /opt/VRTS/bin/vxdisksetup -if \$i;done"
	RExec root $node 'vxdisk list'
fi
exp_cdsdisk=`echo "$out"|grep -i auto:cdsdisk|grep -i online|grep -vP "export|remote"|awk '{print $1}'|xargs -n10000|sed -r "s/ / |/g"`
[ -z "$exp_cdsdisk" ] && oLog error "There is no disks with auto:cdsdisk layout" && myexit 249
exp_thin=`echo "$out"|grep -i auto:cdsdisk|grep -i online|grep -v export|grep thinrclm|awk '{print $1}'|xargs -n10000|sed -r "s/ / |/g"`
[ -z "$exp_thin" ] && exp_thin=no_thin_disk
adisk=`getDiskSizeDgByVxlist $node|grep -vP "^\s*$"` || myexit 201
[ -z "$adisk" ] && oLog error "Failed to get disk size." && myexit 201
adisk0=`echo "$adisk"|awk '$3=="-" {print $1 " " $2}'|grep -P "$exp_cdsdisk "|grep -vP "$exp_thin "|sort -k 2 -rn|awk '{print $0 " thick"}'`
adisk1=`echo "$adisk"|awk '$3=="-" {print $1 " " $2}'|grep -P "$exp_cdsdisk "|grep -P "$exp_thin "|sort -k 2 -rn|awk '{print $0 " thin"}'`
adisk=`echo -e "$adisk0\n$adisk1"|grep -v "^$"`
if [ "$opt" = share ]
then
	disk_node_line=`echo "$adisk"|awk '{print $1}'|xargs -n1000000`
	disk_detail_node=`getDiskDetail $node "$disk_node_line"` || exit 201
	for i in `echo "$NODES"|sed "s/$node//g"`
	do
		RExec root $i "vxdisk scandisks;vxdisk -o alldgs list"
		out=`echo "$out"|grep -i auto:cdsdisk|grep -i online|grep -vP "export|remote"|awk '$4=="-"{print $1}'|xargs -n1000000`
		disk_detail_other=`getDiskDetail $i "$out"` || exit 201
		disk_detail_other=`echo "$disk_detail_other"|awk '{print $2}'|xargs -n100000|sed -r "s/ /|/g"`
		disk_detail_node=`echo "$disk_detail_node"|awk '$2 ~ /'$disk_detail_other'/{print }'`
		[ -z "$disk_detail_node" ] && oLog error "Failed to get share disks" && myexit 1
	done
	disk_detail_node_disk=`echo "$disk_detail_node"|awk '{print $1}'|xargs -n100000|sed -r "s/ /|/g"`
	echo "$adisk"|awk '$1 ~ /'$disk_detail_node_disk'/{print }' > $BASE/tmp/adisk.$PID
	echo "$disk_detail_node"|awk '{print $2 " " $3}' > $BASE/tmp/disk_detail_node.$PID
	paste -d " " $BASE/tmp/adisk.$PID $BASE/tmp/disk_detail_node.$PID
	rm -f $BASE/tmp/adisk.$PID $BASE/tmp/disk_detail_node.$PID
else
	echo "$adisk"
fi
}

getDiskBySizeWithPath(){
#DES:Get disks by Size(opt could only be local or share,path could be a number)
#I just consider the unit is MB currently,here need enhanced.
#size should be without unit
local node size0 size1 i getdisklog opt
node=$1
size0=$2
opt=$3
path=$4
getdisklog=$logs/$tc.getdisk.$opt.log
adiskfile=$logs/$tc.$opt.adisk
if [ "$opt" = local -o "$opt" = share ]
then
        :
else
        oLog error "Invaild var opt \"$opt\" in getDisk"
        myexit 201
fi
if [[ "$size0" =~ ^[0-9]+$ ]]
then
	:
else
	oLog error "syntax error,size can only be a number counting by uint MB"
	myexit 1
fi
oLog "des" "Getting disk list by specified size"
[ -f $adiskfile ] && adisk=`cat $adiskfile`
if [ -z "$adisk" ]
then
	adisk=`getDisk $node "$opt"` || exit 201
	[ -n "$path" ] && adisk=`echo "$adisk"|awk '$5>="'$path'"{print}'`	
fi
echo "Avaiable DISK:" > $getdisklog
echo "$adisk" >> $getdisklog
adiskn=`echo "$adisk"|wc -l`
size1=0
for i in `seq $adiskn`
do
        size2=`echo "$adisk"|sed -n "$i"p|awk '{print $2}'`
        size1=`echo "$size1+$size2"|bc`
        [ `echo "$size1>=$size0"|bc` = 1 ] && break
done
if [ `echo "$size1<$size0"|bc` = 1  ]
then
	oLog error "Failed to get enough disks"
        myexit 1
else
	echo -e "\n\nDISKS Found:\n" >> $getdisklog
        echo "$adisk"|sed -n "1,$i"p|awk '{print $1}'|xargs -n10000 | tee -a $getdisklog
        echo "$adisk"|sed "1,$i"d > $adiskfile
fi
}

snapshotAddmir(){
#DES:Add snap shot mirror
local  node dg vol size freesize adddisk dgdetail
node=$1
dg=$2
vol=$3
size=$4
oLog des "Adding mirror for volume $vol"
size=`echo "$size"+1|bc|cut -d . -f 1`
RExec root $node "vxassist -g $dg maxsize"
freesize=`echo "$out"|grep -oP "\d+(?=\w+\))"|cut -d . -f 1`
if [ -n "$freesize" ] && [ $freesize -lt $size ]
then
	adddisk=`getDiskBySizeWithPath $node "$size" local` || exit 201
        RExec root $node "/opt/VRTS/bin/vxdg -g $dg adddisk $adddisk" 
fi

RExec root $node "vxprint -g $dg"
dgdetail=`echo "$out"|awk '$3=="'$vol'" {print}'`
echo "$dgdetail"|grep ^dc  > /dev/null 2>&1 || RExec root $node "vxsnap -g $dg prepare $vol"
echo "$dgdetail"|grep SNAPDONE  > /dev/null 2>&1 && RExec root $node "vxsnap -g $dg rmmir $vol" 
RExec root $node "NOEXIT:vxsnap -g $dg addmir $vol" 
if [ "$result" != Passed ] && echo "$out"|grep -i "not enough" > /dev/null 2>&1 
then
	adddisk=`getDiskBySizeWithPath $node "$size" local` || exit 201
        RExec root $node "/opt/VRTS/bin/vxdg -g $dg adddisk $adddisk"
        RExec root $node "vxsnap -g $dg addmir $vol"
fi      
sleep 5
RExec root $node "vxprint -g $dg" "$vol"'-02.*SNAPDONE'
RExec root $node "vxedit -g $dg set putil2=dbed_flashsnap $vol-02"
}

snapshotRMmir(){
#DES:Remove snapshot mirror
local node dg vol dgdetail i
node=$1
dg=$2
vol=$3
oLog des "Removing mirror for volume $vol"
for i in `seq 60`
do
	RExec root $node "vxprint -g $dg"
	echo "$out"|grep SNAPTMP > /dev/null 2>&1 || break
	sleep 5
done
dgdetail=`echo "$out"|awk '$3=="'$vol'" {print}'`
echo "$dgdetail"|grep -P SNAPDONE  > /dev/null 2>&1 && RExec root $node "vxsnap -g $dg rmmir $vol"
echo "$dgdetail"|grep ^dc  > /dev/null 2>&1 && RExec root $node "vxsnap -g $dg unprepare $vol" 
}

rmVolumeBeginWithStringFromDg(){
#DES:revove volume which begin with string from diskgroup
local node dg string vol
node=$1
dg=$2
string=$3
oLog des "Removing volumes which begin with $string from $dg \"$dg\" on node \"$node\" "
RExec root $node "vxprint -g $dg|awk '\$1==\"v\" && \$2 ~ /^$string/ {print}'"
for vol in `echo "$out"|awk '{print $2}'`
do
	RExec root $node "vxedit -g $dg -rf rm $vol"
done
}

rmFreeDiskFromDg(){
#DES:remove free disk from all diskgroup
local node dg disk reclaimdisk
node=$1
oLog des "Removing free disk of node \"$node\""
RExec root $node "vxprint|grep dm"
reclaimdisk=`echo "$out"|awk '{print $2}'|xargs -n10000`
RExec root $node "NOEXIT:vxdisk reclaim $reclaimdisk"
#RExec root $node "/opt/VRTS/bin/vxlist disk|grep imported|awk '\$5==\$6{print \$4 \" \" \$3}'"
RExec root $node "vxdg -qa free|awk '\$5==0 {print}'"
for dg in `echo "$out"|awk '{print $1}'|sort -n|sort -u`
do
	disk=`echo "$out"|grep $dg|awk '{print $2}'|xargs -n10000`
	[ -n "$disk" ] && RExec root $node "NOEXIT:vxdg -g $dg rmdisk $disk"
done
}

cleanALLDg(){
#DES:Destory all dgs with created by autotc
oLog des "Clean all Diskgroups except fendg and oradg"
local node dg vxfendg importdg importdgs
node=$1
RExec root $node "[ -f /etc/vxfendg ] && cat /etc/vxfendg || exit 0"
vxfendg=`echo "$out"|grep -vP "^\s*$"`
RExec root $node "NOEXIT:vxdisk -o alldgs list"
if [ -z "$vxfendg" ]
then
	importdgs=`echo "$out"|grep -oP "(?<=\()\w+"|grep -v oradg|sort -n |sort -u`
else
	importdgs=`echo "$out"|grep -oP "(?<=\()\w+"|grep -v $vxfendg|grep -v oradg|sort -n |sort -u` 
fi
for importdg in $importdgs
do
	RExec root $node "NOEXIT:vxdg -Cf import $importdg"
	[ $? -eq 0 ] || forceDestroyDg $node $importdg
done
RExec root $node "NOEXIT:vxdg list"
for dg in `echo "$out"|sed 1d|awk '{print $1}'|grep -v oradg`
do
	RExec root $node "NOEXIT:vxdg destroy $dg"
	[ $? -eq 0 ] || forceDestroyDg $node $dg
done
}
setupDiskByDD(){
#DES:force initiallize disk by dd
local node disks i
node=$1
disks=$2
[ -z "$disks" ] && return 0
RExec root $node "NOEXIT:for i in $disks; do dd if=/dev/zero of=/dev/vx/dmp/\$i bs=1024k count=100; sleep 1; /opt/VRTS/bin/vxdisksetup -if \$i; done"
}
setupDiskByCleanKey(){
#DES:force initiallize disk by clear key
local node disks i diskfile
node=$1
disks=$2
diskfile=/tmp/diskfile.$PID
[ -z "$disks" ] && return 0
echo "$disks"|RExec root $node "cat > $diskfile"
RExec root $node "NOEXIT:vxfenadm -ak 1 -f $diskfile && vxfenadm -ck 1 -f $diskfile;rm -f $diskfile"
disks=`cat "$disks"|awk -F "/" '{print $NF}'|xargs -n 10000`
RExec root $node "NOEXIT:echo \"$disks\"|xargs -n1 vxdisk -f init"
}
forceCleanInvalidDg(){
#DES:force clean all invalid disk group
local node importdg dg disks
node=$1
RExec root $node "vxdisk scandisks;vxdisk -o alldgs list"
importdg=`echo "$out"|grep -oP "(?<=\()[^ )]+"|sort -n|sort -u`
for dg in $importdg
do
        RExec root $node "NOEXIT:vxdg import $dg"
done
RExec root $node "vxdisk -o alldgs list"
disks=`echo "$out"|grep -P "\(\w+\)"|awk '{print "/dev/vx/rdmp/" $1}'`
setupDiskByCleanKey $node "$disks"
RExec root $node "vxdisk -o alldgs list"
disks=`echo "$out"|grep -P "\(\w+\)"|awk '{print $1}'|xargs -n10000`
setupDiskByDD $node "$disks"
}
forceDestroyDg(){
local node dg disks
node=$1
dg=$2
diskfile=/tmp/disk.$PID
RExec root $node "[ -f /etc/vxfendg ] && cat /etc/vxfendg || exit 0"
vxfendg=`echo "$out"|grep -vP "^\s*$"`
if [ -z "$dg" ]
then
	RExec root $node "vxdisk -o alldgs list"
	out=`echo "$out"|sed 1d|grep -P "$exp_encl"|grep -v oradg`
	[ -n "$vxfendg" ] && out=`echo "$out"|grep -v $vxfendg`
else
	RExec root $node "vxdisk -o alldgs list"
	out=`echo "$out"|awk '$4=="'$dg'"||$4=="('$dg')"  {print}'`
fi
echo "$out"|awk '{print "/dev/vx/rdmp/" $1}' > $diskfile
cat $diskfile | $SSH $node "cat > $diskfile"
RExec root $node "NOEXIT:vxfenadm -ak 1 -f $diskfile && vxfenadm -ck 1 -f $diskfile"
disks=`cat $diskfile|awk -F "/" '{print $NF}'|xargs -n 10000`
[ -n "$disks" ] && RExec root $node "NOEXIT:echo \"$disks\"|xargs -n1 vxdisk -f init"
rm -f $diskfile
RExec root $node "rm -f $diskfile"
}

destroyDg(){
#DES:Destroy the specified DiskGroup
local node dg opt vxfendg dgdetail
node=$1
dg=$2
opt=$3
RExec root $node "/opt/VRTSsfmh/adm/dclisetup.sh"
RExec root $node "/opt/VRTS/bin/vxlist dg"
if ! echo "$out"|grep " $dg " > /dev/null 2>&1 
then
	oLog des "Warning: Diskgroup $dg doesn't exist,exitting..."
	return 0
else
	dgdetail=(`echo "$out"|grep " $dg "`)
	if [ "${dgdetail[3]}" = "enabled" ]
	then
		RExec root $node "vxdg list $dg"
		echo "$out"|grep coordinator > /dev/null 2>&1 && opt="-o coordinator"
		RExec root $node "vxdg $opt destroy $dg"
	else
		if [ "$opt" = "-f" ]
		then
			RExec root $node "NOEXIT:vxdg -Cf import $dg" && RExec root $node "vxdg destroy $dg" || forceDestroyDg $node $dg
		else
			RExec root $node "vxdg -Cf import $dg && vxdg list $dg"
			echo "$out"|grep coordinator > /dev/null 2>&1 && opt="-o coordinator"
			RExec root $node "vxdg $opt destroy $dg"
		fi
	fi
fi
}

setDmpNativeSupport(){
#DES:Change dmp_native_support status(status could only be on or off)
local node nodes status reboot rebootnode
nodes=$1
status=$2
if [ "$status" = on -o "$status" = off ]
then
	:
else
	oLog error "status could only be on or off"
	myexit 1
fi
oLog des "setting dmp_native_support to be $status"
for node in $nodes
do
        RExec root $node "vxdmpadm gettune dmp_native_support"
        if echo "$out"|awk '$1=="dmp_native_support"{print $2}'|grep -v $status > /dev/null 2>&1
	then
		RExec root $node "NOERROR:vxdmpadm settune dmp_native_support=$status"
		echo "$out"|grep reboot > /dev/null 2>&1 && reboot=1 || reboot=0
        	RExec root $node "vxdmpadm gettune dmp_native_support"
		if echo "$out"|awk '$1=="dmp_native_support"{print $2}'|grep -v $status > /dev/null 2>&1
		then
			oLog error "Failed to set dmp_native_support to be $status"
			myexit 1
		fi
		[ "$reboot" = 1 ] && sleep 5 && rebootNode $node && rebootnode+=" $node"
	fi
done
sleep 5
for node in $rebootnode
do
	waitNodeOnline $node
	RExec root $node "vxdmpadm gettune dmp_native_support"
done
}
getPathByDmpNode(){
#DES:Get disk path through dmp node name,dmpnode could be multi name seperated by space
local node dmpnode i path paths opt
node=$1
dmpnode=$2
opt=$3
if [ -z "$dmpnode" ]
then
	oLog error "Plase define dmpnode first before you use getPathByDmpNode"
	myexit 1
fi
RExec root $node "vxdmpadm getsubpaths"
for i in $dmpnode
do
	paths=`echo "$out"|grep -P "ENABLED\(A\).*$i "`
	if [ "$opt" = all ]
	then
		path+=" `echo "$paths"|awk '{print $1}'|xargs -n 100`"
	elif echo "$paths"|grep "\(P\)" > /dev/null 2>&1
	then
		path+=" `echo "$paths"|grep "\(P\)"|head -1|awk '{print $1}'`"	
	else
		path+=" `echo "$paths"|head -1|awk '{print $1}'`"
	fi
done
[ $type = L ] && path=`echo "$path"|xargs -n1|awk '{print "/dev/" $1}'`
echo "$path"|xargs -n 100000
}
removeDiskFromVxvm(){
#DES:remove disk from vxvm management,dmpnode could be multi name seperated by space
local dmpnode node
dmpnode=$1
RExec root $NODE1 "/opt/VRTS/bin/vxdiskunsetup -Cf $dmpnode && vxdisk rm $dmpnode"
#for node in $OTHER
#do
#	RExec root $node "vxdisk scandisks;vxdisk rm $dmpnode"
#done
}
getNode2DmpNodeByNode1DmpNode(){
#DES:get the dmpnode name of 2nd node according to the dmpnode name of 1st node
local node1 node2 name1 name2 udid disk
node1=$1
node2=$2
name1=$3
RExec root $node1 "vxdisk list $name1"
udid=`echo "$out"|grep ^udid:|awk '{print $2}'`
RExec root $node2 "vxdisk list"
disk=`echo "$out"|sed 1d|awk '{print $1}'|xargs -n100000000`
RExec root $node2 "vxdisk list $disk"
name2=`echo "$out"|xargs -n 10000000000|sed -r "s/Device:/\nDevice:/g;"|grep " $udid "|grep -oP "(?<=Device: )[^ ]+"|head -1`
RExec root $node2 "vxdisk list $name2"
echo $name2
}
makeDgByLayout(){
#DES:make dg with one or more layout (layout could be s(stripe),sm(stripe-mirror),m(mirror),ms(mirror-stripe),c(concat) )
local node dg layout  ndg i count n j avdisks
node=$1
layout=$2
ndg=$3
opt=$4
i=0
[ -z "$ndg" ] && ndg=1
layout=`echo "$layout"|sed -r 's/,/ /g'`
for ly in $layout
do
        if [ "$ly" = s ]
        then
                i=$[$i+1]
        elif [ "$ly" = sm ]
        then
                i=$[$i+2]
        elif [ "$ly" = m ]
        then
                i=$[$i+1]
        elif [ "$ly" = ms ]
        then
                i=$[$i+2]
        elif [ "$ly" = c ]
        then
                i=$[$i+1]
        else
                oLog error "Can't find the right layout"
                myexit 201
        fi
done
avdisks=`getDisk $node share` || exit 201
count=`echo "$avdisks"|wc -l`
n=$[$count/($i*$ndg)]
if [ -n "$autotcdefinencol" ]
then
        numcol=$autotcdefinencol
        if [ $n -lt $numcol ]
        then
                oLog error "Not enough available disks for testing"
                myexit 201
        fi
else
        numcol=4
fi
if [ $n -ge $numcol ]
then
        numcol=$numcol
elif [ $n -ge 2 ]
then
        numcol=$n
else
        oLog error "Not enough available disks for testing"
        myexit 201
fi
j=$[$i*$numcol]
for dg in `seq $ndg`
do
        disks=`echo "$avdisks"|head -$j|awk '{print $1}'|xargs -n1000`
        if [ "$opt" = ns ]
        then
                RExec root $node "/opt/VRTS/bin/vxdg init autotcdg$dg $disks"
        else
                RExec root $node "/opt/VRTS/bin/vxdg -s init autotcdg$dg $disks"
        fi
        avdisks=`echo "$avdisks"|sed 1,"$j"d`
done
}
makeDgByLayoutForScsi3Fault(){
#DES:make dg with one or more layout (layout could be s(stripe),sm(stripe-mirror),m(mirror),ms(mirror-stripe),c(concat) )
local node dg layout  ndg i count n j avdisks
node=$1
layout=$2
ndg=$3
opt=$4
i=0
[ -z "$ndg" ] && ndg=1
layout=`echo "$layout"|sed -r 's/,/ /g'`
for ly in $layout
do
        if [ "$ly" = s ]
        then
                i=$[$i+1]
        elif [ "$ly" = sm ]
        then
                i=$[$i+2]
        elif [ "$ly" = m ]
        then
                i=$[$i+1]
        elif [ "$ly" = ms ]
        then
                i=$[$i+2]
        elif [ "$ly" = c ]
        then
                i=$[$i+1]
        else
                oLog error "Can't find the right layout"
                myexit 201
        fi
done
avdisks=`getDisk $node share |awk '$5 > 1{print}'` || exit 201
count=`echo "$avdisks"|wc -l`
n=$[$count/($i*$ndg)]
if [ -n "$autotcdefinencol" ]
then
        numcol=$autotcdefinencol
        if [ $n -lt $numcol ]
        then
                oLog error "Not enough available disks for testing"
                myexit 201
        fi
else
        numcol=4
fi
if [ $n -ge $numcol ]
then
        numcol=$numcol
elif [ $n -ge 2 ]
then
        numcol=$n
else
        oLog error "Not enough available disks for testing"
        myexit 201
fi
j=$[$i*$numcol]
for dg in `seq $ndg`
do
        disks=`echo "$avdisks"|head -$j|awk '{print $1}'|xargs -n1000`
        if [ "$opt" = ns ]
        then
                RExec root $node "/opt/VRTS/bin/vxdg init autotcdg$dg $disks"
        else
                RExec root $node "/opt/VRTS/bin/vxdg -s init autotcdg$dg $disks"
        fi
        avdisks=`echo "$avdisks"|sed 1,"$j"d`
done
}
makeVolumeByLayout(){
#DES:make volumes with one or more layout
local node dg layout i voldisks disks
node=$1
dg=$2
layout=$3
size=$4
i=1
[ -z "$numcol" ] && numcol=2
RExec root $node "/opt/VRTS/bin/vxdisk list"
disks=`echo "$out"|grep $dg|awk '{print $1}'`
size=`echo "$size"|sed -r "s/g|G/\*1024/"|bc|cut -d . -f 1`
layout=`echo "$layout"|sed -r 's/,/ /g'`
for ly in $layout
do
	if [ "`echo "$disks"|wc -w`" -lt $numcol ]
	then
		oLog error "Disks quantity is not enough"
		myexit 1
	fi
        case $ly in
                  s)
			oLog des "creating volume with layout=stripe"
                        voldisks=`echo "$disks"|head -$numcol|xargs -n1000`
                        RExec root $node "/opt/VRTS/bin/vxassist -g $dg maxsize layout=stripe $voldisks"
                        msize=`echo "$out"|grep -oP "(?<=volume size: )[0-9]+"|awk '{print $0 "/2048"}'|bc`
                        [ $size -le $msize ] && size=$size || size=$msize
                        RExec root $node "/opt/VRTS/bin/vxassist -g $dg make ${dg}_r0_$i $[$size*2048] layout=stripe ncol=$numcol $voldisks"
                        disks=`echo "$disks"|sed 1,"$numcol"d`
			echo "${dg}_r0_$i $size"
                        ;;

                 sm)
			oLog des "creating volume with layout=stripemirror"
                        voldisks=`echo "$disks"|head -$[$numcol*2]|xargs -n1000`
                        RExec root $node "/opt/VRTS/bin/vxassist -g $dg maxsize layout=stripe-mirror $voldisks"
                        msize=`echo "$out"|grep -oP "(?<=volume size: )[0-9]+"|awk '{print $0 "/2048"}'|bc`
                        [ $size -le $msize ] && size=$size || size=$msize
                        RExec root $node "/opt/VRTS/bin/vxassist -g $dg make ${dg}_r10_$i $[$size*2048] layout=stripe-mirror ncol=$numcol $voldisks"
                        disks=`echo "$disks"|sed 1,"$[$numcol*2]"d`
			echo "${dg}_r10_$i $size"
                        ;;

                  m)
			oLog des "creating volume with layout=mirror"
                        [ $[$numcol%2] -eq 0  ] && numcol=$numcol || numcol=$[$numcol-1]
                        voldisks=`echo "$disks"|head -$numcol|xargs -n1000`
                        RExec root $node "/opt/VRTS/bin/vxassist -g $dg maxsize layout=mirror $voldisks"
                        msize=`echo "$out"|grep -oP "(?<=volume size: )[0-9]+"|awk '{print $0 "/2048"}'|bc`
                        [ $size -le $msize ] && size=$size || size=$msize
                        RExec root $node "/opt/VRTS/bin/vxassist -g $dg make ${dg}_r1_$i $[$size*2048] layout=mirror nmirror=$numcol $voldisks"
                        disks=`echo "$disks"|sed 1,"$numcol"d`
			echo "${dg}_r1_$i $size"
                        ;;

                 ms)
			oLog des "creating volume with layout=mirrorstripe"
                        [ $[$numcol%2] -eq 0  ] && numcol=$numcol || numcol=$[$numcol-1]
                        voldisks=`echo "$disks"|head -$[$numcol*2]|xargs -n1000`
                        RExec root $node "/opt/VRTS/bin/vxassist -g $dg maxsize layout=mirror-stripe $voldisks"
                        msize=`echo "$out"|grep -oP "(?<=volume size: )[0-9]+"|awk '{print $0 "/2048"}'|bc`
                        [ $size -le $msize ] && size=$size || size=$msize
                        RExec root $node "/opt/VRTS/bin/vxassist -g $dg make ${dg}_r01_$i $[$size*2048] layout=mirror-stripe ncol=$numcol $voldisks"
                        disks=`echo "$disks"|sed 1,"$[$numcol*2]"d`
			echo "${dg}_r01_$i $size"
                        ;;

                 c)
			oLog des "creating volume with layout=concat"
                        voldisks=`echo "$disks"|head -$numcol|xargs -n1000`
                        RExec root $node "/opt/VRTS/bin/vxassist -g $dg maxsize layout=concat $voldisks"
                        msize=`echo "$out"|grep -oP "(?<=volume size: )[0-9]+"|awk '{print $0 "/2048"}'|bc`
                        [ $size -le $msize ] && size=$size || size=$msize
                        RExec root $node "/opt/VRTS/bin/vxassist -g $dg make ${dg}_r_$i $[$size*2048] layout=concat ncol=$numcol $voldisks"
                        disks=`echo "$disks"|sed 1,"$numcol"d`
			echo "${dg}_r_$i $size"
                        ;;

                 *)
                        oLog error "Can't find the right layout type"
                        myexit 1
                        ;;
        esac
	i=$[$i+1]
done
}
getDgVolumeDmpnodeMap(){
#DES:get the dmpnode info by dg and volume
local node
node=$1
RExec root $node "vxprint -hvt"
echo "$out"|xargs -n100000000000|sed -r "s/Disk group:/\nDisk group:/g"|while read dgdata
do
        dg=`echo "$dgdata"|grep -oP "(?<=Disk group: )[^ ]+"`
        echo "$dgdata"|sed -r "s/ v /\n&/g"|grep -P "^ v "|while read voldata
        do
                vol=`echo "$voldata"|awk '$1=="v"{print $2}'`
                [ -n "$sv" ] && [[ "$vol" =~ $sv ]] && continue
                if echo "$voldata"|grep " sv " > /dev/null 2>&1
                then
                        sv=`echo "$voldata"|sed -r "s/ sv /\n&/g"|awk '$1=="sv"{print $4}'|xargs -n1000|sed "s/ /|/g"`
                        sd=`echo "$dgdata"|sed -r "s/ v /\n&/g"|grep -P "^ v "|awk '$2 ~ /'$sv'/ {print}'|grep -oP "(?<=sd )\w+"|xargs -n10000`
                else
                        sd=`echo "$voldata"|grep -oP "(?<=sd )\w+"|xargs -n10000`
                fi
                echo "$dg:$vol:$sd"
        done
done
}
MakeFenceDg(){
#DES:Make the fencing disk group
local disks
disks=`getDisk $NODE1 share` || exit 201
disks=`echo "$disks"|sort -k 2 -rn|tail -3|awk '{print $1}'|xargs -n10`
if [ `echo "$disks"|awk '{print NF}'` -ne 3 ]
then
	oLog error "Failed to get enough disks to make fencing dg"
	myexit 201
fi
RExec root $NODE1 "vxdg -o coordinator=on init autotcfendg $disks"
}
disablePathByDg(){
#DES:disable paths acorrding to dg name
local node dg opt disks paths
node=$1
dg=$2
opt=$3
disks=`getDgVolumeDmpnodeMap $node|grep $dg|cut -d : -f 3|xargs -n1000`
RExec root $node "vxdisk list $disks" 'state=enabled'
paths=`getPathByDmpNode $node "$disks" all|sed "s/ /,/g"`
if [ -z "$paths" ]
then
        oLog error "Failed to get paths of ocrvote disks in function disablePathByDg"
        myexit 1
fi
RExec root $node "vxdmpadm -f disable path=$paths"
RExec root $node "vxdg list $dg" 'failed'
RExec root $node "vxdg list $disks" 'state=disabled' 'state=enabled'
}
includeDisks(){
#DES:include specified disks or all into vxvm manage,disk could be empty or sperated by space
local node disk disks file no1 no2
node=$1
disks=$2
echo "$tc"|grep fss > /dev/null 2>&1 || return 0
file=/etc/vx/vxvm.exclude
if [ -z "$disks" ]
then
	RExec root $node "cat -n $file"
	no1=`echo "$out"|grep paths|awk '{print $1}'`
	no2=`echo "$out"|grep "#"|head -1|awk '{print $1}'`
	disks=`echo "$out"|sed -n "$no1,$no2"p|awk '{print $4}'|sort -n|sort -u|xargs -n10000`
fi
[ -n "$disks" ] && RExec root $node "for disk in $disks; do vxdmpadm include dmpnodename=\$disk; done"
}
unexportDisks(){
#DES:unexport exported disks on the node
local node disk disks
node=$1
disks=$2
echo "$tc"|grep fss > /dev/null 2>&1 || return 0
if [ -z "$disks" ]
then
	RExec root $node "vxdisk list"
	disks=`echo "$out"|grep exported|awk '{print $1}'|xargs -n10000`
fi
[ -n "$disks" ] && RExec root $node "for disk in $disks; do vxdisk unexport \$disk; done"
}
waitMirrorPlexWithStatus(){
#DES:wait for some plexs turn to the status when try to plugin disks
local node dg plex plex0 i status plex_exp
node=$1
dg=$2
plex=$3
status=$4
plex_exp=`echo "$plex"|sed "s/ /|/g"`
if [ -z "$plex" ]
then
	oLog error "you must define plex first in funciton waitMirrorPlexError"
	myexit 1
fi
oLog des "Wating for plex \"$plex\" turn to $status"
for i in {1..60}
do
	RExec root $node "vxprint -g $dg"
	plex0=`echo "$out"|grep $status|awk '$2 ~ /'$plex_exp'/{print $2}'|xargs -n1000`
	[ "$plex" = "$plex0" ] && break
	sleep 60
done
if [ "$plex" != "$plex0" ]
then
	oLog error "Time out to wait plex \"$plex\" turn to $status"
	myexit 1
fi
}
waitDiskWithStatus(){
#DES:wait for the disks you specified turn to the status,disks should be sperated by space if multi
local node disk disks status disk_exp
node=$1
disks=$2
status=$3
disk_exp=`echo "$disks"|sed "s/ /|/g"`
oLog des "Wating for disk \"$disks\" turn to $status"
for i in {1..24}
do
        RExec root $node "vxdisk scandisks;vxdisk list | awk '\$1 ~ /$disk_exp/{print}'"
        echo "$out"|grep -iv $status > /dev/null 2>&1 || break
        sleep 5 
done
if echo "$out"|grep -iv $status > /dev/null 2>&1
then
        oLog error "Time out to wait disks \"$disks\" turn to $status"
        myexit 1
fi
}
checkDiskKeys(){
#DES:check the disk of dg have right keys
local node dg num i disk disks nkey
node=$1
dg=$2
num=$3
RExec root $node "vxdisk -o alldgs list"
disks=`echo "$out"|grep $dg|awk '{print $1}'|xargs -n 100`
[ -n "$disks" ] && RExec root $node "for disk in $disks; do /sbin/vxfenadm -s /dev/vx/rdmp/\$disk|egrep \"Device|Tot\"; done"
for nkey in `echo "$out"|grep Tot|grep -oP "\d+"`
do
        [ $nkey -ne $num ] && oLog error "The device's keys should be $num, but the keys are $nkey!!!" && myexit 1
done
}
getShareDiskPathNum(){
#DES:get the share disk's total numbers on all nodes
local n num node total_num i nodenum disks
total_num=0
disks=`getDisk $NODE1 share|awk '$5 > 1{print $1}'|xargs -n10000`
for node in $NODES
do
        RExec root $node "/sbin/vxdisk list $disks"
        n=`echo "$out"|xargs -n 1000000|grep -oP "(?<=numpaths: )[0-9]+"|sort -u|wc -l`
        [ $n -ne 1 ] && oLog error "The disk's paths are different on each node" && myexit 1
        num=`echo "$out"|xargs -n 1000000|grep -oP "(?<=numpaths: )[0-9]+"|sort -u`
        [ -n "$nodenum" ] && [ $nodenum -ne $num ] && oLog error "The number of paths are different on all nodes" && myexit 1
        nodenum=$num
        total_num=$[$total_num+$num]
done
echo "$total_num"
}
clearSfcache(){
#DES:clear all sfcache device
for node in $NODES
do
        RExec root $node "/opt/VRTS/bin/sfcache list"
        cacheareas=`echo "$out"|grep -v NAME|awk '{print $1}'|xargs -n100`
        [ -n "$cacheareas" ] && for cachearea in $cacheareas
        do
                RExec root $node "/opt/VRTS/bin/sfcache offline $cachearea"
                RExec root $node "/opt/VRTS/bin/sfcache delete $cachearea"
        done
done
}
 
renameDmpnode(){
#DES:rename dmpnodename in the clear env step
local node names namemap i j n1 n2
node=$1
RExec root $node "vxdisk list"
names=`echo "$out"|grep "^tmp"|awk '{print $1}'|xargs -n100000`
[ -z "$names" ] && return 0
RExec root $node "vxdisk list $names"
namemap=`echo "$out"|grep -P "^Device:|^disk:"|awk '{print $2}'|xargs -n2|sed "s/name=//g;s/ /,/"`
for i in $namemap
do
	n1=`echo $i|cut -d , -f 1`
	n2=`echo $i|cut -d , -f 2`
	RExec root $node "vxdmpadm setattr dmpnode $n1 name=$n2"
done
}

makeVolset(){
#DES:make volset with followed volumes
local node dg vset vol vols vol_1 vol_other
node=$1
dg=$2
vset=$3
vols=$4
vol_1=`echo "$vols"|awk '{print $1}'`
vol_other=`echo "$vols"|sed "s/$vol_1//"`
RExec root $node "vxvset -g $dg make $vset $vol_1"
for vol in $vol_other
do
        RExec root $node "vxvset -g $dg addvol $vset $vol"
done
}

pathManage(){
#DES:Finish path operations on vxvm disks.(disk coulbe one for multi seperated by ,;do could be one of (list,enable,disable))
local node disk disk_exp pathdata do num disk0 file column
node=$1
disk=$2
do=$3
file=$BASE/tmp/pathinfo.$PID
if [ -z "$node" -o -z "$disk" -o -z "$do" ]
then
        oLog error "Missing options in funciton pathMange"
        myexit 1
fi

disk_exp=`echo "$disk"|sed -r "s/,/ | /g;s/^|$/ /g"`
RExec root $node "vxdmpadm getsubpaths"
column=`echo "$out"|awk '{print NF}'|sort -n|tail -1`
pathdata=`echo "$out"|sed 1,2d|xargs -n$column|grep -P "$disk_exp"`
for disk0 in `echo "$disk"|sed "s/,/ /g"`
do
        echo "$pathdata"|grep -P " $disk0 "|awk '{print $1 "," $2}'|xargs -n100000000|awk '{print "'$disk0'" " " $0}'
done > $file
pathdata=`cat $file`
path=`echo "$pathdata"|grep -oP "[^ ]+(?=,)"|xargs -n1000000|sed "s/ /,/g"`
rm -f $file
LExec "echo \"$pathdata\""
if [ "$do" = list ]
then
        :
elif [ "$do" = disable ]
then
        RExec root $node "vxdmpadm -f disable path=$path"
elif [ "$do" = enable ]
then       
        RExec root $node "vxdmpadm enable path=$path"
fi
}
