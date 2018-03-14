getHostnameOSProduct(){
#DES:Gettiing Hostname,OS version and product info,will check if it is in support if you specify support_os
local node update local support_os
node=$1
support_os=$2
oLog des "Getting hostname of node"
RExec root $node "hostname"
oLog des "Getting os version"
RExec root $node "uname"
type=`echo "$out"|cut -c 1`
if [ -n "$support_os" ] && ! echo "$support_os"|sed "s/,/ /g"|xargs -n1|grep -P "^$type$" > /dev/null 2>&1
then
	oLog error "The OS is not supported" 
	myexit 201
fi
case $type in
        L)
                cmd0='[ -f /etc/redhat-release ] && cat /etc/redhat-release || cat /etc/issue'
                cmd1='for i in `rpm -qa|grep -i vrts`; do echo Package INFO: $i; rpm -qi $i; echo; done'
                cmd2="df -h|sed 1d|xargs -n 6"
		cmd3='uname -r'
                ;;
        A)
                cmd0='oslevel -s'
                cmd1='lslpp -l|grep -i vrts'
                cmd2="df -g|sed 1d|xargs -n 7"
                ;;
        S)
                cmd0='cat /etc/release'
                cmd1="for i in \`pkginfo|grep VRTS|awk '{print \$2}'\`; do echo Package INFO: \$i; pkginfo -l \$i; echo; done"
                cmd2='df -h|sed 1d|xargs -n 6'
                ;;
        *)
                oLog error "OS Version is not support"
                myexit 249
esac
echo "cmd2='$cmd2'" >> $logs/define
RExec root $node "$cmd0"
case $type in
	L)
		#rhel6u5,centos6u5,sles11sp2
		if echo "$out"|grep "Red Hat" > /dev/null 2>&1
		then
			autotcos=`echo "$out"|grep -oP "[567]{1}\.*\d*"|xargs -n10|sed -r "s/5|6|7/rhel&/;s/\./u/g"|tr [A-Z] [a-z]`
		elif echo "$out"|grep "CentOS" > /dev/null 2>&1
		then
			autotcos=`echo "$out"|grep -oP "[567]{1}\.*\d*"|xargs -n10|sed -r "s/5|6|7/centos&/;s/\./u/g"|tr [A-Z] [a-z]`
		else
			autotcos=`echo $out|grep -oP " 10 (SP)*\d* | 11 (SP)*\d* | 12 (SP)*\d* "|xargs -n10|sed -r "s/10|11|12/sles&/;s/ //g"|tr [A-Z] [a-z]`
		fi
                RExec root $node "$cmd3" && autotckernel="$out"
		;;
	A)
		#aix71tl4
		autotcos=`echo "$out"|sed -r "s/([0-9]{2})[0-9]{2}-([0-9]{2}).*/\1tl\2/;s/^/aix/"`
		;;
	S)
		#solaris10u10,solaris11u2
		if echo "$out"|grep "Solaris 10" > /dev/null 2>&1
		then
			update=`echo "$out"|grep -oP "(?<=u)\d+"`
			autotcos="solaris10u$update"
		elif echo "$out"|grep "Solaris 11" > /dev/null 2>&1
		then
			update=`echo "$out"|grep -oP "(?<=11\.)\d+"`
			autotcos="solaris11u$update"
                        RExec root $node "pkg info entire" 
                        autotcsru=`echo "$out"|grep -oP "(?<=Oracle Solaris )[^\)]+"|tail -1`
		fi
		;;
esac
[ -z "$autotcos" ] && oLog error "Your OS is not supported" && myexit 249
[ $type = L ] && RExec root $node "$cmd3" && autotckernel="$out"
if [ "$isvcs" != no ]
then
	oLog des "Getting package data of InfoScale Product"
	RExec root $node "$cmd1"
fi
}
checkOSVers(){
#DES:check OS version higher than input,need after function getHostnameOSProduct(os1 should be like sles11,rhel6,aix71tl04,solaris10u10)
local os1 os0 n
os1=$1
case $type in 
	L)
		if [[ $autotcos =~ rhel ]]
		then
			os0=`echo -e "$os1\n$autotcos"|grep -oP "rhel\d+"`
		elif [[ $autotcos =~ sles ]]
		then
			os0=`echo -e "$os1\n$autotcos"|grep -oP "sles\d+"`
		fi
		;;
	A)
		os0=`echo -e "$os1\n$autotcos"|grep -oP "aix\w+"`
		;;
	S)
		os0=`echo -e "$os1\n$autotcos"|grep -oP "solaris\w+"`
		;;
esac
n=`echo "$os0"|wc -l`
os0=`echo "$os0"|sort -n|tail -1`
if [ $n -eq 2 ] && [ "$os0" = "$autotcos" ] 		
then
	oLog des "The OS version meets requirement"
else
	oLog error "The OS version doesn't meet requirement"
	myexit 201
fi
}
checkProductVersByVxvm(){
#DES:check Product version higher than or equal to input,need after function getHostnameOSProduct
local vers0 vers1 vers2
vers0=$1
oLog des "check if product is higher than $vers0"
if [ "$type" = L ] 
then
	vers1=`echo "$out"|grep -oP "(?<=VRTSvxvm-)[^-]+"|head -1`
elif [ "$type" = A ]
then
	vers1=`echo "$out"|grep VRTSvxvm|awk '{print $2}'|head -1`
elif [ "$type" = S ]
then
	vers1=`echo "$out"|grep -A 6 VRTSvxvm|grep -oP "(?<=VERSION:  )[^,]+"`
fi
if [ -z "$vers0" ] || [ -z "$vers1" ]
then
	oLog error "Failed to check if the product version meets requirement"
	myexit 201
fi
vers2=`echo -e "$vers0\n$vers1"|sort -n|head -1`
if [ $vers1 = $vers2 ] && [ $vers1 != $vers0 ]
then
	oLog error "The product version doesn't meet requirement"
	myexit 201
fi
oLog des "The product version meet requirement" 
}

dropNativeDg(){
local line detail cmdfile lvmdisk
cmdfile=$BASE/tmp/dropnativevg.$PID
oLog des "Drop native vg/zpool"
case $type in
        L)
                RExec root $NODE1 "NOEXIT:pvs|grep autotc"
		echo "$out"|awk '$3 ~ /lvm[0-9]+/{print}'|while read line
		do
			detail=($line)
			[[ ${detail[3]} =~ ^ax ]] && echo "vgimport ${detail[1]}"
			[[ ${detail[3]} =~ ^a ]] && echo "vgremove -f ${detail[1]}"
			echo "pvremove ${detail[0]}"
		done|grep -vP "^\s*$" > $cmdfile
		[ `cat $cmdfile|wc -l` -eq 0 ] && rm -f $cmdfile && return 0
		LExec "cat $cmdfile"
		user=root;host=$NODE1;cmd=$cmdfile
		out=`cat $cmdfile|$SSH $NODE1 "cat > /tmp/dropnativevg.$PID;sh /tmp/dropnativevg.$PID 2>&1"`
		rm -f $cmdfile
		result=Passed
		oLog exec
                ;;
        A)
		for node in $OTHER
		do
			RExec root $node "NOEXIT:for vg in \`lsvg|grep ^autotc\`; do varyoffvg \$vg; exportvg \$vg; done"
		done
		RExec root $NODE1 "NOEXIT:for fs in \`lsfs|grep autotc|awk '{print \$3}'\`; do rmfs \$fs; done"
		RExec root $NODE1 "NOEXIT:for vg in \`lsvg|grep ^autotc\`; do varyonvg \$vg; disk=\`lsvg -p \$vg 2>/dev/null|tail -1|awk '{print \$1}'\`; reducevg -d -f \$vg \$disk; done"	
                ;;
        S)
		RExec root $NODE1 "NOEXIT:for pool in \`zpool import|grep ^pool:|awk '{print \$2}'|grep autotc\`; do echo import \$pool; zpool import \$pool; done"
		RExec root $NODE1 "NOEXIT:for pool in \`zpool list|grep ^autotc|awk '{print \$1}'\`; do echo destroy \$pool; zpool destroy \$pool; done"
                ;;
        *)
                oLog des "OS Version is not support"
                myexit 1
esac
RExec root $NODE1 "vxdisk list"
lvmdisk=`echo "$out"|grep -i lvm|grep -oP \"^\w+_\w+\"`
RExec root $NODE1 "NOEXIT:for disk in $lvmdisk; do dd if=/dev/zero of=/dev/vx/dmp/\$disk bs=1024k count=100; done"
}
makeNativeDg(){
#DES:Create native vg/zpool
local node dg disk epv
node=$1
dg=$2
disk=$3
oLog des "creating native vg/zpool"
case $type in 
        L)
		RExec root $node "[ -f /etc/lvm/lvm.conf.bk ] || cp -pf /etc/lvm/lvm.conf /etc/lvm/lvm.conf.bk"
		RExec root $node "multipath -ll > /dev/null 2>&1 && multipath -F > /dev/null 2>&1 || (exit 0)"
		RExec root $node "NOEXIT:pvcreate -y $disk"
		RExec root $node "NOEXIT:vgcreate $dg $disk"
		RExec root $node "NOEXIT:vgs" "$dg"
		if [ $result != Passed ]
		then
			RExec root $node "(echo o;echo n;echo p;echo 1;echo;echo;echo w)|fdisk $disk"
			RExec root $node "fdisk -l $disk"
			disk=`echo "$out"|tail -1|awk '{print $1}'`
                	RExec root $node "NOEXIT:pvcreate -y $disk"
                	RExec root $node "NOEXIT:vgcreate $dg $disk"
			RExec root $node "vgs" "$dg"
		fi
                ;;
	A)
		RExec root $node "mkvg -y $dg $disk"
		;;
	S)
		RExec root $node "zpool create -f $dg $disk"
		;;
        *)
                oLog des "OS Version is not support"
                myexit 1
esac
}
makeNativeLv(){
#DES:Create native lv,if opt=fs,then make local fs
local node dg lv size opt fs
node=$1
dg=$2
lv=$3
size=$4
opt=$5
[ "$opt" = fs ] && oLog des "Create native lv and make filesystem" ||  oLog des "Create native lv"
case $type in
        L)
		fs=`getNativeFs`
                RExec root $node "lvcreate -n $lv -L $size $dg"
		[ "$opt" = fs ] && RExec root $node "mkfs -t $fs /dev/$dg/$lv"
                ;;
        A)
		RExec root $node "mklv -y $lv $dg $size"
		[ "$opt" = fs ] && RExec root $node "crfs -v jfs -m /$lv -d $lv"
                ;;
        S)
		RExec root $node "zfs create $dg/$lv && zfs set mountpoint=legacy $dg/$lv"
                ;;
        *)
                oLog des "OS Version is not support"
                myexit 1
esac
}
makeUFS(){
#DES:for solaris only to make a ufs mount point
local node disk disk0 mp
node=$1
disk=$2
mp=$3
disk0=`echo $disk|sed -r "s/s2$//"`
if [[ "$disk" =~ ^[a-zA-Z0-9]+s2$ ]]
then
	RExec root $node "(echo label;echo 0;echo y;echo q)|format -e $disk0"
else
	RExec root $node "(echo label;echo 0;echo y;echo y;echo;echo;echo;echo no;echo q)|format -e $disk0"
fi
RExec root $node "echo y|newfs /dev/rdsk/$disk"
RExec root $node "mkdir -p /$mp && mount -F ufs /dev/dsk/$disk /$mp"
}
mountNativeFS(){
#DES:Mount native filesystem
local node dg lv fs
node=$1
dg=$2
lv=$3
oLog des "Mount the native filesystem"
case $type in
        L)
		fs=`getNativeFs`
		RExec root $node "mkdir -p /$lv && mount -t $fs /dev/$dg/$lv /$lv"
                ;;
        A)
		RExec root $node "mkdir -p /$lv && mount /$lv"
                ;;
        S)
		RExec root $node "mkdir -p /$lv && mount -F zfs $dg/$lv /$lv"
                ;;
        *)
                oLog des "OS Version is not support"
                myexit 1
esac
RExec root $node "$cmd2" "/$lv$"
}
vgPoolDeport(){
#DES:Deport the native dg or pool
local node dg
node=$1
dg=$2
oLog des "Deport native dg or pool for $dg on $node"
case $type in
        L)
		RExec root $node "vgchange -an $dg && vgexport $dg"
                ;;
        A)
		RExec root $node "varyoffvg $dg && exportvg $dg"
                ;;
        S)
		RExec root $node "zpool export $dg"
                ;;
        *)
                oLog des "OS Version is not support"
                myexit 1
esac
}

vgPoolImport(){
#DES:Import the native dg or pool
local node dg disk major
node=$1
dg=$2
disk=$3
major=$4
oLog des "Import native dg or pool for $dg on $node"
case $type in
        L)
                RExec root $node "vgscan && vgimport $dg && vgchange -ay $dg && vgdisplay -v $dg"
                ;;
        A)
		[ -z "$major" ] &&  RExec root $node "importvg -y $dg $disk && varyonvg $dg && lsvg $dg" || RExec root $node "importvg -y $dg -V $major -n $disk"
                ;;
        S)
		RExec root $node "zpool import -f $dg"
                ;;
        *)
                oLog des "OS Version is not support"
                myexit 1
esac
}
getMajorNum(){
local node nodes major
nodes=$1
oLog des "Getting Major number for $node"
for node in $nodes
do
	RExec root $node "lvlstmajor"
	major+=" `echo "$out"|grep -oP "\d+"|xargs -n100`"
done
echo "$major"|xargs -n1|sort -n|tail -1
}

genExpect0(){
#DES:Generate interaction script accroding to your response,single question matching one by one
local node response timeout line expect cmd timeout_cmd
node=$1
response=$2
script=$BASE/tmp/expect.exp.$PID
echo -e "#!/usr/bin/expect\nset timeout 20\nspawn $SSH $node" > $script
echo "$response"|grep -vP "^\s*$"|while read line
do
	expect=`echo $line|awk -F ",,," '{print $1}'`
	cmd=`echo $line|awk -F ",,," '{print $2}'`
	timeout=`echo $line|awk -F ",,," '{print $3}'`
	echo "$line"|grep notmust > /dev/null 2>&1 && timeout_cmd='' || timeout_cmd=';exit 2'
	[ -z "$expect" ] && oLog error "Failed to generate $script" && myexit 1
	[ -z "$timeout" ] && timeout=20
	echo -e "expect {\n\t\"$expect\" {send \"$cmd\\\r\"}\n\ttimeout {puts \"\\\nEXPECT ERROR.Timeout to find '$expect'\"$timeout_cmd}\n}" >> $script
	echo "set timeout $timeout" >> $script
done
echo -e "expect {\n\t\"#\" {send \"exit 0\\\r\"}\n\teof {exit 1}\n\ttimeout {puts \"\\\nEXPECT ERROR.Timeout to find '#'\";exit 2}\n}\nexpect eof" >> $script
}

genExpect1(){
#DES:Generate interaction script accroding to your response,multi question matching.For some complex scenario
local node response timeout line expect cmd timeout_cmd i
node=$1
response=$2
i=1
timeout_cmd=';exit 2'
script=$BASE/tmp/expect.exp.$PID
echo -e "#!/usr/bin/expect\nset timeout 20\nspawn $SSH $node" > $script
echo "$response"|grep -vP "^\s*$"|while read line
do
	expect=`echo $line|awk -F ",,," '{print $1}'`
	cmd=`echo $line|awk -F ",,," '{print $2}'`
	[ -z "$expect" ] && oLog error "Failed to generate $script" && myexit 1
	if [ $i -eq 1 ]
	then
		echo -e "expect {\n\t\"$expect\" {send \"$cmd\\\r\"}\n\ttimeout {puts \"\\\nEXPECT ERROR.Timeout to find '$expect'\"$timeout_cmd}\n}" >> $script	
		echo -e "set timeout _TIMEOUT_\nwhile { 1 } {\n\texpect {" >> $script
	else
		echo -e "\t\t\"$expect\" {send \"$cmd\\\r\"}" >> $script
	fi
	i=$[$i+1]
done
echo -e "\t\t\"#\" {send \"exit 0\\\r\";break}\n\t\ttimeout {puts \"\\\nEXPECT ERROR.Unkown Question '_QUESTION_'\";exit 2;break}\n\t}\n\tsleep 0.1\n}\nexpect eof" >> $script
timeout=`echo "$response"|awk -F ",,," '{print $3}'|grep -vP "^\s*$"|sort -n|tail -1`
replaceString _TIMEOUT_ $timeout $script || myexit 201
}

interactByResponse(){
#DES:Do interactions according to responose,if interrupt has value,interaction will be interupted when reading the value of interrupt
local count line question node response line0 expectout expectin tmpfile expectpid expectret cmd
method=$1
node=$2
response=$3
interrupt=$4

LExec "noexit:$BASE/etc/expect_test.exp $node"
if [ $? -ne 0 ]
then
        oLog error "The PROMPT of node $node is not supported by ITF(ITF support #)"
	myexit 1
fi

expectin=$BASE/tmp/expect.exp.$PID
expectout=$BASE/tmp/expect.out.$PID
tmpfile=/tmp/expect.$PID
genExpect$method $node "$response" || exit 1
LExec "cat $expectin"
echo -e "$expectin >> $expectout 2>&1 && echo expectresult:0 >> $expectout || echo expectresult:1 >> $expectout" > $tmpfile
chmod +x $tmpfile $expectin
line0=`cat $olog|wc -l|awk '{print $1 "+1"}'|bc`
host=`hostname`
user=root
cmd=$expectin
nohup $tmpfile > /dev/null 2>&1 &
sleep 5
expectpid=`ps -ef|grep -P "expect.exp.$PID$|expect.$PID$"|grep -v grep|awk '{print $2}'|xargs -n 100`
while true
do	
	sleep 1
	cat $expectout|grep expectresult > /dev/null 2>&1 && break
	sed -i "$line0",'$'d $olog
	out=`cat $expectout` 
	if [ -n "$interrupt" ] && echo "$out" | grep "$interrupt" > /dev/null 2>&1
	then
		kill -9 $expectpid
		echo -e "\nInterrupt testing...\nexpectresult:2" >> $expectout 
	fi
	oLog exec
	question=`echo "$response"|awk -F ",,," '{print $1}'|grep -vP "^\s*$"|tr "\n" "|"|sed -r "s/\|$/\n/"`
	count=`cat $olog|grep -P "$question"|uniq -c|awk '{print $1}'|sort -n|tail -1`
	if [ -n "$count" ] && [ "$count" -gt 5 ]
	then
		kill -9 $expectpid
		echo -e "\n\nTCERROR:The interaction went into a loop\nexpectresult:1" >> $expectout
	fi
done
expectret=`tail -10 $expectout|grep -oP "(?<=expectresult:)\d+"`
if [ $expectret = 0 ]
then
	result=Passed
elif [ $expectret = 2 ]
then
	result=NOERROR:Failed
else
	result=Failed
fi
sed -i "$line0",'$'d $olog
out=`cat $expectout` 
oLog exec
rm -f $tmpfile $expectin $expectout
line=`cat -n $olog |grep _QUESTION_|grep -v timeout|awk '{print $1}'`
if [ -n "$line" ]
then
	line0=$[$line-10]
	question=`sed -n "$line0,$line"p $olog|grep -vP "^\s*$|_QUESTION_"|tail -1`
	sed -i -r ""$line"a\ \nEXPECT ERROR.Unkown Question '$question'" $olog
	sed -i "$line"d $olog
fi
[ $result = Failed ] && myexit 1
}
getCksum(){
#DES:get the cksum value of the target you specified,if target is file,it exports the files cksum value;if target is directory,it exports cksum value of all files under.
local node value target
node=$1
target=$2
if $SSH $node "[ -d \"$target\" ]"
then
	RExec root $node "find $target -type f|grep -v lost|sort -n|xargs cksum"
elif $SSH $node "[ -f \"$target\" ]"
then
	RExec root $node "cksum $target"
else
	oLog error "invalid target to get cksum value"
	myexit 1
fi
}
getNativeFs(){
local fs exception except os
exception="sles11:ext3,"
os=`echo "$autotcos"|grep -oP "^[a-z]+\d+"|head -1`
except=`echo "$exception"|grep -oP "(?<=$os:)\w+"`
if [ -n "$autotcdefinefs" ]
then
	fs=$autotcdefinefs
elif [ -n "$except" ]
then
	fs=$except
else
	$SSH $NODE1 "mkfs.ext4" 2>&1 |grep -iP "not\s+found" > /dev/null 2>&1 && fs=ext3 || fs=ext4
fi
echo "$fs"
}
clearNfsClient(){
local pid mp dfpid
[ -z "$nfsclient" ] && return 0
oLog des "Going to clear mount point on the nfsclient"
RExec root $nfsclient "ps -ef|grep tmpfile"
pid=`echo "$out"|grep -v grep |awk '{print $2}'|xargs -n100`
[ -n "$pid" ] && RExec root $nfsclient "NOEXIT:kill -9 $pid"
ssh $nfsclient "$cmd2" > /dev/null 2>&1 &
sleep 20
dfpid=`ps -ef|grep -v grep|grep $nfsclient|awk '{print $2}'|xargs -n100` 
if [ -n "$dfpid" ]
then
	kill -9 $dfpid
else
	mp=`echo "$out"|grep /autotc|awk '{print $6}'|xargs -n 100`
	[ -n "$mp" ] && RExec root $nfsclient "NOEXIT:for i in $mp; do umount \$i;done"
	[ -f "$BASE/lock/$nfsclient" ] && LExec "NOEXIT:rm -rf $BASE/lock/$nfsclient"
fi
}
clearFile(){
#DES: delete files and directories created by auto case
local node files file
files="/etc/vx/encryption"
for node in $NODES
do 
	RExec root $node "for file in $files;do [ -d \$file ] && rm -rf \$file || echo 0;done"
done
}

clearMisc(){
clearFile
clearNfsClient
}
getNicByIp(){
#DES:find out the nic name by ip
local node ip
node=$1
ip=$2
if [[ $ip =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]
then
	:
else
	ip=`turnNodesToIp $ip` || exit 1
fi
RExec root $node "ifconfig -a"
echo "$out"|grep -B 10 "$ip"|grep -oP "^\w+"|tail -1
}
formatMaskAddress(){
#DES:turn the hexadecimal to decimal
local mask netmask
mask=$1
if echo $mask|grep 0x >/dev/null 2>&1
then
        netmask=`echo $mask |sed -r 's/\w{2}/& /g'|cut -d ' ' -f2-5`
else
        netmask=`echo $mask |sed -r 's/\w{2}/& /g'`
fi
echo `for i in $netmask; do echo -n $((16#$i )) ; done|sed -r 's/\w{3}/&./g'`
}
getNicAndStatus(){
#DES:show the nic names of the node
local node dev speed link
node=$1
case $type in 
	L)
		RExec root $node "ifconfig -a"
		for dev in `echo "$out"|grep -oP "^e\w+"`
		do
			RExec root $node "ifconfig $dev up && sleep 5 && ethtool $dev"
			link=`echo "$out"|grep -oP "(?<=detected: )\w+"|tr [A-Z] [a-z]`
			speed=`echo "$out"|grep -oP "(?<=peed: )\w+"`
			[ -z "$speed" ] && speed=-
			echo "$dev $link $speed"
		done
		;;
	A)
		RExec root $node "lsdev -Cc adapter"
		for dev in `echo "$out"|grep ^ent|awk '{print $1}'|sed "s/ent/en/g"`
		do
			if echo "$out"|grep Virtual > /dev/null 2>&1
			then
				echo "$dev yes 1000Mb/s"
			else
				RExec root $node "ifconfig $dev up && sleep 5 && entstat -d $dev"
				echo "$out"|grep -iP "Link\s*Status\s*:\s*up" > /dev/null 2>&1 && link=yes || link=no
				speed=`echo "$out"|grep "Media Speed Running: "|grep -oP "\d+"`Mb/s
				echo "$dev $link $speed"
			fi
		done
		;;
	S)
		RExec root $node "dladm show-link"
		for dev in `echo "$out"|grep -v LINK|awk '{print $1}'`
		do
			RExec root $node "ifconfig -a|grep $dev || ipadm create-ip $dev"
			RExec root $node "ifconfig $dev up && sleep 5 && dladm show-link $dev"
			echo "$out"|grep -i up > /dev/null 2>&1 && link=yes || link=no
			speed="-"
			echo "$dev $link $speed"
		done
esac
}
configureTmpIPOnNode(){
#DES:configure ip address on node (mask could be empty)
local node ip $nic
node=$1
nic=$2
ip=$3
mask=$4
[ -z "$mask" ] && mask=255.255.255.0
case $type in
	L)
		RExec root $node "ifconfig $nic $ip netmask $mask"
		;;
	A)
		RExec root $node "ifconfig $nic $ip netmask $mask"
		;;
	S)
		RExec root $node "ifconfig $nic $ip netmask $mask"
esac
}
ListDetailByMountPoint(){
#DES:List the detail info mount point(CAP USE FREE USEPER DEV MP),outout will be a num with unit=MB (mp could be multi seperated by ,)
local node line cap use free useper dev mp mp_exp
node=$1
mp=$2
mp_exp=`echo "$mp"|sed -r "s/,/\$|/g;s/$/\$/"`
[ -z "$type" -o -z "$cmd2" ] && oLog error "type or cmd2 is undefined in getDiskSizeDgByVxlist" && exit 1
RExec root $node "$cmd2"
[ -n "$mp" ] && out=`echo "$out"|grep -P "$mp_exp"`
echo "$out"|while read line
do
	case $type in 
		L)
			for i in 2 3 4
			do
				echo "$line"|awk '{print $'$i'}'|sed -r "s/m|M//;s/g|G/*1024/;s/t|T/*1024*1024/"|bc|cut -d . -f 1
			done|xargs -n1000 echo -n
			echo -n " "
			for i in 5 1 6
			do
				echo "$line"|awk '{print $'$i'}'
			done|xargs -n1000 echo -n
			;;
		A)
			cap=`echo "$line"|awk '{print $2 "*1024"}'|bc|cut -d . -f 1`
			free=`echo "$line"|awk '{print $3 "*1024"}'|bc|cut -d . -f 1`
			use=$[$cap-$free]
			echo -n "$cap $use $free "
                        for i in 4 1 7
                        do
                                echo "$line"|awk '{print $'$i'}'
                        done|xargs -n1000 echo -n	
			;;
		S)
                        for i in 2 3 4
                        do
                                echo "$line"|awk '{print $'$i'}'|sed -r "s/m|M//;s/g|G/*1024/;s/t|T/*1024*1024/"|bc|cut -d . -f 1
                        done|xargs -n1000 echo -n
			echo -n " "
                        for i in 5 1 6
                        do
                                echo "$line"|awk '{print $'$i'}'
                        done|xargs -n1000 echo -n
	esac
	echo
done
}
getFillinNum(){
#DES:Get the num with unit=MB how much data we need fill in to archive the percentage
local node mp per data
node=$1
mp=$2
per=$3
per=`echo $per|grep -oP "\d+"`
data=(`ListDetailByMountPoint $node "$mp"`) || exit 1
echo "${data[0]}*$per/100-${data[1]}"|bc|cut -d . -f 1
}

getMaskAndGatewayByIp(){
#DES:get netmask and gateway by target(could be hostname or ipaddress)
local node ip mask gateway network target
node=$1
target=$2
[ -z "$type" ] && oLog error "OS type is not defined" && myexit 1
if [[ $target =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]
then
        :
else
        target=`turnNodesToIp $target` || exit 1
fi
RExec root $node "ifconfig -a"
if [ $type = L ]
then
        mask=`echo "$out"|grep "$target "|sed -r "s/\:/ /g"|grep -oP "(?<=[Mm]ask )[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+"`
else
        mask=`echo "$out"|grep "$target "|grep -oP "(?<=netmask )[\w]+"`
        mask=`formatMaskAddress $mask` || exit 1
fi
[ -z "$mask" ] && oLog error "Failed to get netmask by $target" && myexit 1
LExec "ipcalc -n $target $mask"
network=`echo "$out"|grep -oP "[\d\.]+(?=\.0)"`
RExec root $node "netstat -rn"
gateway=`echo "$out"|awk '$1 ~ /0.0.0.0|default/ {print $2}'|grep $network`
echo "$mask $gateway"            
}

checkNfsStatus(){
#DES:Check nfs client status
oLog des "check the $nfsclient is available for testing"
checkSshAuthorize root $nfsclient
[ $? -ne 0 ] && oLog error "please check the ssh login host without password" && myexit 1
dfpid=`nohup ssh -l root $nfsclient "df -h" >/dev/null 2>&1 &`
sleep 60
if ps -ef|grep ssh|grep $nfsclient >/dev/null 2>&1
then
        LExec "kill -9  `ps -ef|grep ssh|grep $nfsclient|awk '{print $2}'`"
        RExec root $nfsclient "nohup reboot -nf > /dev/null 2>&1 &"
        waitNodeOffline $nfsclient
        waitNodeOnline $nfsclient
fi
echo "nfsclient='$nfsclient'" >> $logs/define
}
formatToCdsdisk(){
#DES:format ZFS and simple disks to cdsdisk
local node
node=$1
RExec root $node "vxdmpadm listenclosure"
encl=`echo "$out"|grep -viP "ENCLR_NAME|===|disk|scsi"|awk '{print $1}'`
[ -n "$encl" ] && exp_encl=`echo "$encl"|xargs -n100|sed -r 's/ /|/g'`
RExec root $node "/opt/VRTS/bin/vxdisk list"
other_disk=`echo "$out"|grep -iE "ZFS|simple|nolabel"|awk '/'$exp_encl'/ {print $1}'|xargs -n10000`
[ -n "$other_disk" ] && RExec root $node "NOEXIT:for disk in $other_disk; do dd if=/dev/zero of=/dev/vx/dmp/\$disk bs=1024k count=10
0; /opt/VRTS/bin/vxdisksetup -if \$disk format=cdsdisk; done"
}
