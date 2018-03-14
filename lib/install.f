installSF(){
#DES:install infoscale product
local version version0 installfile installer base cmd patcha os_comp os vers productid
mp=/autotcinst
version=$1
freshinstall=$2
if [ -z "$version" -o -z "$freshinstall" ]
then
	oLog error "version and freshinstall must be defined first"
	myexit 201
fi
IPS=`turnNodesToIp` || exit 201
setNodeDate
setNodeEquivalence
getInstaller $version
os=`echo $os_comp|cut -d / -f 2`
installer=$installfile
if [[ $installer =~ installmr ]]
then
	version0=`echo $install_base_vers $version|xargs -n1|sort -n|grep -B 1 $version|head -1`
	getInstaller $version0
	base=`dirname $installfile`
	if [ "$freshinstall" = yes ]
	then
		if [ "$noipc" = no ]
		then
			genRspAndExec "$installer -base_path $base $IPS" "$os" "$version0"
		elif [ "$noipc" = yes ]
		then
			genRspAndExec "$installer -noipc -base_path $base -patch_path $patch_path $IPS" "$os" "$version0" 
		fi
	else
		oLog error "To be developed"
		myexit 201
		#genRspAndExec "$installfile $IPS" "$os" "$version"
		#genRspAndExec "$installer $IPS" "$os" "$version0"
	fi
else
	if [ "$noipc" = no ]
	then
		genRspAndExec "$installer $IPS" "$os" "$version"
	elif [ "$noipc" = yes ]
	then
		genRspAndExec "$installer -noipc -patch_path $patch_path $IPS" "$os" "$version"
	fi
	version0=$version
fi
RExec root $NODE1 "NOEXIT:umount /autotcinst"
checkCPIError
#for node in $NODES
#do
#        checkSFPkgStatus pkgcomp $node
#done
cat $olog|grep -P "VCS_START.*not" > /dev/null 2>&1 && setVCSAutoStartStop "$NODES" 1
}
configureSF(){
local response clusname nics i j nic1 nic2
if [ -z "$IPS" ]
then
	IPS=`turnNodesToIp` || exit 201
fi
! [[ "$setup_content" =~ install ]] && setNodeDate && setNodeEquivalence
if [ -z "$installcmd" ]
then
	RExec root $NODE1 "ls /opt/VRTS/install/install*" "install"
	installcmd=`echo "$out"|grep -P "$installcmdfilter"|xargs basename`
fi
clusname=clus`echo "$IPS"|xargs -n1|cut -d . -f 4|xargs -n100|sed "s/ //g"`
nics=`getHeartbeatLink` || exit 201
for i in $nics
do
	j=`echo $i|sed -r "s/,/\n/g"|sort -n|sort -u|wc -l`
	if [ $j -ne 1 ]
	then
		oLog error "The private Nic name are not the same on nodes,please check"
		myexit 201
	fi
done
nic1=`echo "$nics"|sed -n 1p|cut -d , -f 1`
nic2=`echo "$nics"|sed -n 2p|cut -d , -f 1`
rspfile=configure_sfrac.rsp
response=`cat $BASE/etc/install/$rspfile|sed "s/_INSTALL_CMD_/$installcmd/;s/_IP_/$IPS/;s/_CLUSNAME_/$clusname/;s/_NIC1_/$nic1/;s/_NIC2_/$nic2/"`
interactByResponse 1 $NODE1 "$response"
if checkCVMStatus 
then
	:
else
	oLog error "Failed to configure SFRAC"
	myexit 201
fi
checkCPIError
}
fencingSF(){
local disks dg importdg i fencedg
if [ -z "$IPS" ]
then
	IPS=`turnNodesToIp` || exit 201
fi
! [[ "$setup_content" =~ install ]] && setNodeDate && setNodeEquivalence
if [ -z "$installcmd" ]
then
        RExec root $NODE1 "ls /opt/VRTS/install/install*" "install"
        installcmd=`echo "$out"|grep -P "$installcmdfilter"|xargs basename`
fi
forceCleanInvalidDg $NODE1
RExec root $NODE1 "for i in \`vxdg list|sed 1d|awk '{print \$1}'\`; do vxdg list \$i; done"
fencedg=`echo "$out"|grep -B 6 "coordinator"|grep -P "^Group:"|awk '{print $2}'|grep -vP "^\s*$"`
[ -n "$fencedg" ] && RExec root $NODE1 "for i in $fencedg; do vxdg -o coordinator destroy \$i;done"
RExec root $NODE1 "for i in \`vxdg list|sed 1d|awk '{print \$1}'\`; do vxdg destroy \$i;done"
MakeFenceDg
response=`cat $BASE/etc/install/fencing.rsp|sed "s/_INSTALL_CMD_/$installcmd/;s/_IP_/$IPS/"`
interactByResponse 1 $NODE1 "$response"
RExec root $NODE1 "[ -f /etc/vxfendg ] && cat /etc/vxfendg" 'autotcfendg'
checkCPIError
}
genRspAndExec(){
#DES:execute interaction to install infoscale product
local cmd file os sf response
cmd=$1
os=$2
sf=$3
file=$BASE/tmp/tmpexpect.$PID
if [ -z "$productid" ]
then
	getProductId || exit 201
fi
echo "#,,,$cmd,,,300" > $file
#cat $BASE/etc/install/install_"$os"_"$sf".rsp|grep -v CMD >> $file
cat $BASE/etc/install/install.rsp|grep -v CMD|sed "s/_PRODUCT_/$productid/" >> $file
response=`cat $file`
rm -rf $file
interactByResponse 1 $NODE1 "$response"
}
getProductId(){
local response
echo "#,,,$cmd,,,300" > $file
cat $BASE/etc/install/install_pre.rsp|grep -v CMD >> $file
response=`cat $file`
rm -rf $file
interactByResponse 1 $NODE1 "$response"
productid=`tail -20 $olog|grep -P "$productfilter"|grep -oP "\d+(?=\))"`
if [ -z "$productid" ]
then
	oLog error "Failed to get the Product Id for $productfilter"
	myexit 201
fi
}
getMp(){
#DES:get mount point from server for infoscale product
case $type in
        L)
                osdir=linux
                RExec root $NODE1 '[ -f /etc/redhat-release ] && cat /etc/redhat-release || cat /etc/issue'
                os_comp=`echo "$out"|grep -oP "Red|SUSE|[567]{1}(?=\.)| 10 | 11 | 12 "|xargs -n10|sed -r "s/Red/redhatlinux/;s/SUSE/suselinux/;s/5|6|7/rhel&/;s/10|11|12/sles&/;s/ /\//"`
                ;;
        A)
                osdir=aix
                ;;
        S)
                osdir=sol
		RExec root $NODE1 'uname -a'
		echo "$out" |grep -i sparc > /dev/null 2>&1 && os_comp="sol_sparc" || os_comp="sol_x64"
                ;;
        *)
                oLog error "OS Version is not support"
                myexit 201
esac
nfspath=$install_vault:/re/release_train/$osdir
RExec root $NODE1 "NOERROR:mkdir -p $mp && $cmd2|grep $mp$ > /dev/null 2>&1 && umount $mp"
RExec root $NODE1 "mount $nfspath $mp"
}
getInstaller(){
#DES:get installer path of infoscale product
local version versionflag
version=$1
versionflag=`echo $version|sed -r "s/^[0-9]\.[0-9]$/(&|&.0)/"`
[ -z "$osdir" ] && getMp
RExec root $NODE1 "find $mp/$version/ -type f -name \"install*\""
installfile=`echo "$out"|grep -P "$os_comp.*(installer|installmr)$"|grep -P "${type}xRT\-$versionflag\-"|sort -n|tail -1`
if [ -z "$installfile" ]
then
	oLog error "Failed to get installer path"
	myexit 201
fi
}
getVRTSPkgList(){
#DES:List VRTS package you installed
local node
node=$1
case $type in
	L)
		RExec root $node "NOERROR:rpm -qa|grep VRTS"
		[ -n "$out" ] && echo "$out"|cut -d - -f 1,2
		;;
	A)
		RExec root $node "NOERROR:lslpp -l|grep VRTS"
		[ -n "$out" ] && echo "$out"|awk '{print $1 "-" $2}'
		;;
	S)
		RExec root $node "NOERROR:for i in \`pkginfo|grep VRTS|awk '{print \$2}'\`; do pkginfo -l \$i; echo; done"
		[ -n "$out" ] && echo "$out"|xargs -n1000000000|sed -r "s/PKGINST:/\nPKGINST:/g"|grep -oP "(?<=PKGINST: )\w+|(?<=VERSION: )[^ ,]+"|xargs -n2|sed "s/ /-/"
esac
}
checkSFPkgStatus(){
#DES:check the deployment status of SF product.(opt=pkgcomp,will check pckage on the node;opt=install,0:have installed sf;1:have not installed sf)
local node opt pkg pkg0 file product pkgdiff diffname diffname0 diffnameshort 
opt=$1
node=$2
unset version_not_right_pkg miss_pkg
file=$BASE/etc/install/package.list
if [ "$opt" = pkgcomp ]
then
	product=`cat $olog | grep "Select a product to install: "|grep -oP "\d+$"`
	product=`cat $olog | grep " $product)"`
	[ `echo "$product"|wc -l` -lt 2 ] && oLog des "Warning!Please check the the product your registered"
	product=`echo "$product"|grep -ioP "$productfilter"|tr [A-Z] [a-z]|head -1`
	pkg0=`cat $file|grep "$autotcos:$version:$product"|cut -d : -f 4|sed -r "s/,/\n/g"|grep -vP "^\s*$"`
	if [ -z "$pkg0" ]
	then
		oLog error "Failed to get package list by combination $autotcos:$version0:$product"
		myexit 201
	fi
	pkg=`getVRTSPkgList $node|xargs -n 1000|sed "s/ /|/g"`
	oLog des "Comparing Packages For Node $node:"
	oLog des "Packages should be installed on $node with version or higher: `echo "$pkg0"|xargs -n 1000`"
	oLog des "Packages have been installed on $node: `echo "$pkg"|sed "s/|/ /g"`"
	pkgdiff=`echo "$pkg0"|grep -vP "$pkg"`
	for diffname0 in $pkgdiff
	do
		diffnameshort=`echo $diffname0|cut -d - -f 1`
		diffname=`echo "$pkg"|sed "s/|/ /g"|xargs -n1|grep $diffnameshort`
		if [ -n "$diffname" ]
		then
			latestname=`echo -e "$diffname\n$diffname0"|sort -n|tail -1`
			[ "$latestname" != "$diffname" ] && version_not_right_pkg+=$diffname
		else
			miss_pkg+=$diffnameshort
		fi 
	done
	if [ -n "$miss_pkg" -o -n "$version_not_right_pkg" ]
	then
		[ -n "$miss_pkg" ] && oLog error "Found missing package(s) on $node: $miss_pkg"	
		[ -n "$version_not_right_pkg" ] && oLog error "Found version not right package(s) on $node: $version_not_right_pkg"
	fi
elif [ "$opt" = install ]
then
	RExec root $node "NOERROR:ls /opt/VRTS/install/install*"
	echo "$out"|grep -P "sfrac|installer" > /dev/null 2>&1 && return 0 ||  return 1
fi
}
getHeartbeatLink(){
#DES:get heartbeat combination
local node nicc nodec nics pubnic nicstr i n j k nic nicother kother seg position
file=$BASE/tmp/heartbeat.$PID
j=0
nodec=`echo "$NODES"|awk '{print NF}'`
for node in $NODES
do
	pubnic=`getNicByIp $node $node` || exit 1
	nicstr=`getNicAndStatus $node` || exit 1
	nics[$j]=`echo "$nicstr"|grep -v $pubnic|grep yes|awk '{print $1}'|xargs -n 100`
	j=$[$j+1]
done
nic=(${nics[0]})
seg=1
for i in ${nic[*]}
do
	echo -n "$i" >> $file
	configureTmpIPOnNode $NODE1 $i 192.168."$seg"1.1
	j=1
	for node in $OTHER
	do
		position=$[$j+1]
		usenic=`cat $file|cut -d , -f $position|xargs -n100|sed "s/ /|/g"`
		[ -n "$usenic" ] && nicother=(`echo "${nics[$j]}"|xargs -n1|grep -vP "$usenic"|xargs -n100`) || nicother=(${nics[$j]})
		kother="$j"1
		for n in ${nicother[*]}
		do
			configureTmpIPOnNode $node $n 192.168."$seg"1.$kother
			RExec root $NODE1 "NOEXIT:ping -c 3 192.168."$seg"1.$kother"
			if [ "$result" = Passed ]
			then
				echo -n ",$n" >> $file
				break
			else
				kother=$[$kother+1]
				continue
			fi
			
		done
		j=$[$j+1]
	done
	seg=$[$seg+1]
	echo >> $file
	nicc=`tail -1 $file|awk -F "," '{print NF}'`
	if [ $nicc -ne $nodec ]
	then
		oLog error "Failed to get private Nics"
		myexit 201
	fi
	cat $file|wc -l|grep 2 >/dev/null 2>&1 && break
done
if [ -f $file ] && [ `cat $file|grep -vP "^\s*$"|wc -l` -eq 2 ]
then
	cat $file
	rm -f $file
else
	oLog error "Failed to get private Nics"
	rm -f $file
	myexit 201
fi
}
setVCSAutoStartStop(){
#DES:set vcs automatical start and stop
local node nodes status file
nodes=$1
status=$2
case $type in
	L)
		file=/etc/sysconfig/vcs
		;;
	A)
		file=/etc/default/vcs
		;;
	S)
		file=/etc/default/vcs
esac
for node in $nodes
do
	RExec root $node "perl -i -pe \"s/VCS_START=[0-9]+/VCS_START=$status/;s/VCS_STOP=[0-9]+/VCS_STOP=$status/\" $file"
done
}
installPrepare(){
case $type in
        A)
		
                for node in $NODES
                do
                        RExec root $node "for i in /opt /usr /var ; do df -g|grep \$i\$|awk '{print \$3}'|cut -d . -f 1|awk '{print \$1}'|grep ^0\$ > /dev/null 2>&1 && chfs -a size=+2G \$i; done;chdev -l vscsi0 -a vscsi_err_recov=fast_fail -P;chdev -l vscsi0 -a vscsi_path_to=30 -P"
                done
esac
}
checkCPIError(){
local fail error
fail=0
error=0
#sed -n '/STDIN:umount/,$'p $olog|grep -P "\.\. Failed" > /dev/null 2>&1 && fail=1
cat $olog|grep -P "\.\. Failed" > /dev/null 2>&1 && fail=1
if [ $fail = 1 ]
then
	oLog error "Fond Failed steps in CPI logs"
	myexit 201
fi
}
