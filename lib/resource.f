genLvmSgConf(){
#DES:Generate lvm serivce group config for main.cf.
local systemlist autostartlist i j vg lv fs device flag
vg=$1
lv=$2
fs=$3
i=0
RExec root $NODE1 "cat $autotcmaincf"
flag=`echo "$out"|grep -P "group\s+autotcsg_nativevgpool"|wc -l`
systemlist=`for j in $NODES; do echo -n "$j = $i, "; i=$[$i+1]; done|sed -r "s/, $/\n/"`
autostartlist=`echo $NODES|sed "s/ /, /"`
cat << EOF
group autotcsg_nativevgpool$flag (
        SystemList = { $systemlist }
        AutoStartList = { $autostartlist }
        )

EOF
case $type in
        L)
                device="/dev/mapper/$vg-$lv"
cat <<EOF
        LVMVolumeGroup autotcres_vgpool$flag (
                VolumeGroup = $vg
                StartVolumes = 1
                )
EOF
                ;;
        A)
                device=/dev/$lv
cat <<EOF
        LVMVG autotcres_vgpool$flag (
                VolumeGroup = $vg
                MajorNumber = $majornum
                ImportvgOpt = y
                )
EOF
                ;;
        S)
		device=$vg/$lv
cat <<EOF
        Zpool autotcres_vgpool$flag (
                PoolName = $vg
                ChkZFSMounts = 0
                )
EOF
                ;;
        *)
                oLog des "OS Version is not support"
                myexit 1
esac
cat <<EOF

        Mount autotcres_vgpoolmnt$flag (
                MountPoint = "/$lv"
                BlockDevice = "$device"
                FSType = $fs
                FsckOpt = "-y"
                )

        autotcres_vgpoolmnt$flag requires autotcres_vgpool$flag
EOF
}
genNicSgConf(){
#DES:Generate service group config.
local systemlist autostartlist i j flag automaincf
i=0
automaincf=/etc/VRTSvcs/conf/config/main.cf
RExec root $NODE1 "cat $automaincf"
flag=`echo "$out"|grep -P "group\s+mulNicSG"|wc -l`
case $type in
        L)
                systemlist=`for j in $NODES; do echo -n "$j = $i, "; i=$[$i+1]; done|sed -r "s/, $/\n/"`
                autostartlist=`for j in $NODES; do echo -n "$j, "; done|sed -r "s/, $/\n/"`
                ;;
        A)
                ;;
        S)
                ;;
        *)
                oLog des "OS Version is not support"
                myexit 1
esac
cat << EOF
group mulNicSG (
        SystemList = { $systemlist }
        AutoStartList = { $autostartlist }
        )

        IPMultiNIC ipMulNicRes (
                Address = "$autotcvip"
                MultiNICAResName = mulNicRes
                NetMask = "$mask"
                )

        MultiNICA mulNicRes (
                PingOptimize = 0
                NetMask = "$mask"
                )

        ipMulNicRes requires mulNicRes
EOF
}

genOracleRacSgConf(){
#DES:Generate Oracle Rac serivce group config for main.cf.
local node racconf systemlist autostartlist
racconf=$BASE/tmp/racconf.$PID

RExec root $NODE1 "cat $autotcmaincf"
if echo "$out"|grep -P " CSSD | Oracle " > /dev/null 2>&1 
then
	oLog error "Found CSSD or Oracle service in main.cf,Please check first!"
	myexit 201
fi
i=0
systemlist=`for j in $NODES; do echo -n "$j = $i, "; i=$[$i+1]; done|sed -r "s/, $/\n/"`
autostartlist=`echo $NODES|sed "s/ /, /"`
RExec root $NODE1 "vxdg list"
dgnum=`echo "$out"|grep -P "oradg[0-9]{4}_dbarch|oradg[0-9]{4}_ocrvote"|wc -l`
if [ $dgnum -ne 2 ]
then
        oLog error "Currently,just support oracle installed by OADT"
        myexit 201
fi
flag=`echo "$out"|grep -oP "(?<=oradg)[0-9]{4}"|head -1`

cat << EOF > $racconf
group crs_grp (
        SystemList = { $systemlist }
        Parallel = 1
        AutoStartList = { $autostartlist }
        )

        CFSMount ocrvote_mnt (
                Critical = 0
                MountPoint = "/ocrvote"
                BlockDevice = "/dev/vx/dsk/oradg${flag}_ocrvote/ocrvote"
                )

        CSSD cssd (
                Critical = 0
                CRSHOME = "/crs/crshome"
                OnlineWaitLimit = 5
                OfflineWaitLimit = 3
                )

        CVMVolDg ocrvote_voldg (
                Critical = 0
                CVMDiskGroup = oradg${flag}_ocrvote
                CVMVolume = { ocrvote }
                CVMActivation = sw
                )


        requires group cvm online local firm
        cssd requires ocrvote_mnt
        ocrvote_mnt requires ocrvote_voldg

group oradb_grp (
        SystemList = { $systemlist }
        Parallel = 1
        AutoStartList = { $autostartlist }
        )

        CFSMount oraarch_mnt (
                Critical = 0
                MountPoint = "/archive"
                BlockDevice = "/dev/vx/dsk/oradg${flag}_dbarch/archive"
                )

        CFSMount oradata_mnt (
                Critical = 0
                MountPoint = "/dbdata"
                BlockDevice = "/dev/vx/dsk/oradg${flag}_dbarch/dbdata"
                )

        CVMVolDg data_voldg (
                Critical = 0
                CVMDiskGroup = oradg${flag}_dbarch
                CVMVolume = { dbdata, archive }
                CVMActivation = sw
                )

        Oracle oradb (
                Critical = 0
		_SIDINFO_
                Owner = oracle
                Home = "/oracle/orahome"
                StartUpOpt = SRVCTLSTART
                ShutDownOpt = SRVCTLSTOP
                LevelTwoMonitorFreq = 0
                )

        requires group crs_grp online local firm
        oraarch_mnt requires data_voldg
        oradata_mnt requires data_voldg
        oradb requires oraarch_mnt
        oradb requires oradata_mnt
EOF
for node in $NODES
do
	RExec oracle $node "echo \$ORACLE_SID"
	line="Sid @$node = $out"
	sed -i -r "/_SIDINFO_/i\ \t\t$line" $racconf
done	
sed -i /_SIDINFO_/d $racconf
cat $racconf
rm -f $racconf
}
genOracleSISgConf(){
local systemlist SID
#DES:Generate Oracle SI serivce group config for main.cf.
i=0
systemlist=`for j in $NODES; do echo -n "$j = $i, "; i=$[$i+1]; done|sed -r "s/, $/\n/"`
RExec root $NODE1 "cat $autotcmaincf"
if echo "$out"|grep -P " Oracle " > /dev/null 2>&1 
then
        oLog error "Found Oracle service in main.cf,Please check first!"
        myexit 201
fi
RExec root $NODE1 "vxdg list"
dgnum=`echo "$out"|grep -P "oradg[0-9]{4}_dbarch|oradg[0-9]{4}_ocrvote"|wc -l`
if [ $dgnum -lt 1 ]
then
        oLog error "Currently,just support oracle installed by OADT"
        myexit 201
fi
flag=`echo "$out"|grep -oP "(?<=oradg)[0-9]{4}"|head -1`
RExec oracle $NODE1 'echo $ORACLE_SID'
SID=$out

cat << EOF
group oradb_grp (
                SystemList = { $systemlist }
                AutoStartList = { $NODE1 }
                )

                DiskGroup data_voldg (
                                DiskGroup = oradg${flag}_dbarch
                                Reservation = NONE
                                )

                Mount archive_mnt (
                                MountPoint = "/archive"
                                BlockDevice = "/dev/vx/dsk/oradg${flag}_dbarch/archive"
                                FSType = vxfs
                                FsckOpt = "-y"
                                )

                Mount data_mnt (
                                MountPoint = "/dbdata"
                                BlockDevice = "/dev/vx/dsk/oradg${flag}_dbarch/dbdata"
                                FSType = vxfs
                                FsckOpt = "-y"
                                )

                Netlsnr Ora_Netlsnr (
                                Owner = oracle
                                Home = "/oracle/orahome"
                                TnsAdmin = "/oracle/orahome/network/admin"
                                )

                Oracle oradb (
                                Critical = 0
                                Sid = $SID
                                Owner = oracle
                                Home = "/oracle/orahome"
                                )

                Volume ora_archive (
                                DiskGroup = oradg${flag}_dbarch
                                Volume = archive
                                )

                Volume ora_datavol (
                                DiskGroup = oradg${flag}_dbarch
                                Volume = dbdata
                                )

                Ora_Netlsnr requires oradb
                archive_mnt requires ora_archive
                data_mnt requires ora_datavol
                oradb requires archive_mnt
                oradb requires data_mnt
                ora_archive requires data_voldg
                ora_datavol requires data_voldg
EOF
}

genDgFailoverConf(){
#DES:Generate failover diskgroup config for main.cf
local dg vol mount seq
dg=$1
vol=$2
mount=$3

systemlist=`for j in $NODES; do echo -n "$j = $i, "; i=$[$i+1]; done|sed -r "s/, $/\n/"`
seq=$RANDOM
serivcegroup=privsg$seq
dgservice=privdg$seq
mountservice=privmount$seq

cat << EOF
group $serivcegroup (
                SystemList = { $systemlist }
                AutoStartList = { $NODE1 }
                )

                DiskGroup $dgservice (
                                DiskGroup = $dg
                                )

                Mount $mountservice (
                                MountPoint = "$mount"
                                BlockDevice = "/dev/vx/dsk/$dg/$vol"
                                FSType = vxfs
                                FsckOpt = "-y"
                                )

                $mountservice requires $dgservice
EOF
}

genRacHaSgconfAix(){
#DES:Generate mix service group config for main.cf
local node1 node2 node1nic node2nic vip1 vip2 nic mask gw
args=($*)
node1=${args[0]}
node2=${args[1]}
node1nic=${args[2]}
node2nic=${args[3]}
nic=${args[4]}
vip1=${args[5]}
vip2=${args[6]}
mask=${args[7]}
gw=${args[8]}
dg1=autotcdg1
dg2=autotcdg2
dg3=autotcdg3
cat << EOF
hagrp -add nfs_sg
hagrp -modify nfs_sg SystemList  $node1 0 $node2 1
hagrp -modify nfs_sg AutoFailOver 0
hagrp -modify nfs_sg Parallel 1
hagrp -modify nfs_sg AutoStartList  $node1 $node2
hagrp -modify nfs_sg SourceFile "./main.cf"
hares -add n1 NFS nfs_sg
hares -modify n1 GracePeriod 90
hares -modify n1 NFSSecurity 0
hares -modify n1 LockFileTimeout 180
hares -modify n1 Enabled 1
hares -add ph1 Phantom nfs_sg
hares -modify ph1 Enabled 1
hagrp -add sg12
hagrp -modify sg12 SystemList  $node1 0 $node2 2
hagrp -modify sg12 AutoStartList  $node1
hagrp -modify sg12 SourceFile "./main.cf"
hares -add ${dg2}_sg12 DiskGroup sg12
hares -modify ${dg2}_sg12 DiskGroup $dg2
hares -modify ${dg2}_sg12 StartVolumes 0
hares -modify ${dg2}_sg12 StopVolumes 0
hares -modify ${dg2}_sg12 MonitorReservation 0
hares -modify ${dg2}_sg12 tempUseFence INVALID
hares -modify ${dg2}_sg12 Reservation ClusterDefault
hares -modify ${dg2}_sg12 ClearClone 0
hares -modify ${dg2}_sg12 Enabled 1
hares -add ip_$node1 IP sg12
hares -local ip_$node1 Device
hares -modify ip_$node1 Device $node1nic -sys $node1
hares -modify ip_$node1 Device $node2nic -sys $node2
hares -modify ip_$node1 Address "$vip1"
hares -modify ip_$node1 NetMask "$mask"
hares -modify ip_$node1 PrefixLen 1000
hares -modify ip_$node1 Enabled 1
hares -add mnt_${dg2}_r0_2_$dg2 Mount sg12
hares -modify mnt_${dg2}_r0_2_$dg2 MountPoint "/autotcdir/ITF_3_${dg2}_r0_2"
hares -modify mnt_${dg2}_r0_2_$dg2 BlockDevice "/dev/vx/dsk/$dg2/${dg2}_r0_2"
hares -modify mnt_${dg2}_r0_2_$dg2 FSType vxfs
hares -modify mnt_${dg2}_r0_2_$dg2 MountOpt largefiles
hares -modify mnt_${dg2}_r0_2_$dg2 FsckOpt "%-y"
hares -modify mnt_${dg2}_r0_2_$dg2 SnapUmount 0
hares -modify mnt_${dg2}_r0_2_$dg2 CkptUmount 1
hares -modify mnt_${dg2}_r0_2_$dg2 RecursiveMnt 0
hares -modify mnt_${dg2}_r0_2_$dg2 VxFSMountLock 1
hares -modify mnt_${dg2}_r0_2_$dg2 Enabled 1
hares -add mnt_${dg2}_r10_1_$dg2 Mount sg12
hares -modify mnt_${dg2}_r10_1_$dg2 MountPoint "/autotcdir/ITF_1_${dg2}_r10_1"
hares -modify mnt_${dg2}_r10_1_$dg2 BlockDevice "/dev/vx/dsk/$dg2/${dg2}_r10_1"
hares -modify mnt_${dg2}_r10_1_$dg2 FSType vxfs
hares -modify mnt_${dg2}_r10_1_$dg2 MountOpt largefiles
hares -modify mnt_${dg2}_r10_1_$dg2 FsckOpt "%-y"
hares -modify mnt_${dg2}_r10_1_$dg2 SnapUmount 0
hares -modify mnt_${dg2}_r10_1_$dg2 CkptUmount 1
hares -modify mnt_${dg2}_r10_1_$dg2 RecursiveMnt 0
hares -modify mnt_${dg2}_r10_1_$dg2 VxFSMountLock 1
hares -modify mnt_${dg2}_r10_1_$dg2 Enabled 1
hares -add nfsres_sg12 NFSRestart sg12
hares -modify nfsres_sg12 NFSRes n1
hares -modify nfsres_sg12 LocksPathName "/autotcdir/ITF_1_${dg2}_r10_1"
hares -modify nfsres_sg12 NFSLockFailover 1
hares -modify nfsres_sg12 Enabled 1
hares -add nfsres_sg12_l NFSRestart sg12
hares -modify nfsres_sg12_l NFSRes n1
hares -modify nfsres_sg12_l Lower 1
hares -modify nfsres_sg12_l LocksPathName "/autotcdir/ITF_1_${dg2}_r10_1"
hares -modify nfsres_sg12_l NFSLockFailover 1
hares -modify nfsres_sg12_l Enabled 1
hares -add nic_sg12_$nic NIC sg12
hares -local nic_sg12_$nic Device
hares -modify nic_sg12_$nic Device $node1nic -sys $node1
hares -modify nic_sg12_$nic Device $node2nic -sys $node2
hares -modify nic_sg12_$nic NetworkHosts  "$gw"
hares -modify nic_sg12_$nic PingOptimize 1
hares -modify nic_sg12_$nic Enabled 1
hares -add proxy_sg12 Proxy sg12
hares -modify proxy_sg12 TargetResName n1
hares -modify proxy_sg12 Enabled 1
hares -add share_${dg2}_r0_2_$dg2 Share sg12
hares -modify share_${dg2}_r0_2_$dg2 PathName "/autotcdir/ITF_3_${dg2}_r0_2"
hares -modify share_${dg2}_r0_2_$dg2 Options "rw,root=@10.200.0.0/8"
hares -modify share_${dg2}_r0_2_$dg2 Enabled 1
hares -add share_${dg2}_r10_1_$dg2 Share sg12
hares -modify share_${dg2}_r10_1_$dg2 PathName "/autotcdir/ITF_1_${dg2}_r10_1"
hares -modify share_${dg2}_r10_1_$dg2 Options "rw,root=@10.200.0.0/8"
hares -modify share_${dg2}_r10_1_$dg2 Enabled 1
hares -add vol_${dg2}_r0_2_$dg2 Volume sg12
hares -modify vol_${dg2}_r0_2_$dg2 DiskGroup $dg2
hares -modify vol_${dg2}_r0_2_$dg2 Volume ${dg2}_r0_2
hares -modify vol_${dg2}_r0_2_$dg2 Enabled 1
hares -add vol_${dg2}_r10_1_$dg2 Volume sg12
hares -modify vol_${dg2}_r10_1_$dg2 DiskGroup $dg2
hares -modify vol_${dg2}_r10_1_$dg2 Volume ${dg2}_r10_1
hares -modify vol_${dg2}_r10_1_$dg2 Enabled 1
hagrp -add sg21
hagrp -modify sg21 SystemList  $node2 0 $node1 1
hagrp -modify sg21 AutoStartList  $node2
hagrp -modify sg21 SourceFile "./main.cf"
hares -add ${dg1}_sg21 DiskGroup sg21
hares -modify ${dg1}_sg21 DiskGroup $dg3
hares -modify ${dg1}_sg21 StartVolumes 0
hares -modify ${dg1}_sg21 StopVolumes 0
hares -modify ${dg1}_sg21 MonitorReservation 0
hares -modify ${dg1}_sg21 tempUseFence INVALID
hares -modify ${dg1}_sg21 Reservation ClusterDefault
hares -modify ${dg1}_sg21 ClearClone 0
hares -modify ${dg1}_sg21 Enabled 1
hares -add ip_$node2 IP sg21
hares -local ip_$node2 Device
hares -modify ip_$node2 Device $node1nic -sys $node2
hares -modify ip_$node2 Device $node2nic -sys $node1
hares -modify ip_$node2 Address "$vip2"
hares -modify ip_$node2 NetMask "$mask"
hares -modify ip_$node2 PrefixLen 1000
hares -modify ip_$node2 Enabled 1
hares -add mnt_${dg3}_r0_2_$dg3 Mount sg21
hares -modify mnt_${dg3}_r0_2_$dg3 MountPoint "/autotcdir/ITF_6_${dg3}_r0_2"
hares -modify mnt_${dg3}_r0_2_$dg3 BlockDevice "/dev/vx/dsk/$dg3/${dg3}_r0_2"
hares -modify mnt_${dg3}_r0_2_$dg3 FSType vxfs
hares -modify mnt_${dg3}_r0_2_$dg3 MountOpt largefiles
hares -modify mnt_${dg3}_r0_2_$dg3 FsckOpt "%-y"
hares -modify mnt_${dg3}_r0_2_$dg3 SnapUmount 0
hares -modify mnt_${dg3}_r0_2_$dg3 CkptUmount 1
hares -modify mnt_${dg3}_r0_2_$dg3 RecursiveMnt 0
hares -modify mnt_${dg3}_r0_2_$dg3 VxFSMountLock 1
hares -modify mnt_${dg3}_r0_2_$dg3 Enabled 1
hares -add mnt_${dg3}_r10_1_$dg3 Mount sg21
hares -modify mnt_${dg3}_r10_1_$dg3 MountPoint "/autotcdir/ITF_5_${dg3}_r10_1"
hares -modify mnt_${dg3}_r10_1_$dg3 BlockDevice "/dev/vx/dsk/$dg3/${dg3}_r10_1"
hares -modify mnt_${dg3}_r10_1_$dg3 FSType vxfs
hares -modify mnt_${dg3}_r10_1_$dg3 MountOpt largefiles
hares -modify mnt_${dg3}_r10_1_$dg3 FsckOpt "%-y"
hares -modify mnt_${dg3}_r10_1_$dg3 SnapUmount 0
hares -modify mnt_${dg3}_r10_1_$dg3 CkptUmount 1
hares -modify mnt_${dg3}_r10_1_$dg3 RecursiveMnt 0
hares -modify mnt_${dg3}_r10_1_$dg3 VxFSMountLock 1
hares -modify mnt_${dg3}_r10_1_$dg3 Enabled 1
hares -add nfsres_sg21 NFSRestart sg21
hares -modify nfsres_sg21 NFSRes n1
hares -modify nfsres_sg21 LocksPathName "/autotcdir/ITF_5_${dg3}_r10_1"
hares -modify nfsres_sg21 NFSLockFailover 1
hares -modify nfsres_sg21 Enabled 1
hares -add nfsres_sg21_l NFSRestart sg21
hares -modify nfsres_sg21_l NFSRes n1
hares -modify nfsres_sg21_l Lower 1
hares -modify nfsres_sg21_l LocksPathName "/autotcdir/ITF_5_${dg3}_r10_1"
hares -modify nfsres_sg21_l NFSLockFailover 1
hares -modify nfsres_sg21_l Enabled 1
hares -add nic_sg21_$nic NIC sg21
hares -local nic_sg21_$nic Device
hares -modify nic_sg21_$nic Device $node1nic -sys $node2
hares -modify nic_sg21_$nic Device $node2nic -sys $node1
hares -modify nic_sg21_$nic NetworkHosts  "$gw"
hares -modify nic_sg21_$nic PingOptimize 1
hares -modify nic_sg21_$nic Enabled 1
hares -add proxy_sg21 Proxy sg21
hares -modify proxy_sg21 TargetResName n1
hares -modify proxy_sg21 Enabled 1
hares -add share_${dg3}_r0_2_$dg3 Share sg21
hares -modify share_${dg3}_r0_2_$dg3 PathName "/autotcdir/ITF_6_${dg3}_r0_2"
hares -modify share_${dg3}_r0_2_$dg3 Options "rw,root=@10.200.0.0/8"
hares -modify share_${dg3}_r0_2_$dg3 Enabled 1
hares -add share_${dg3}_r10_1_$dg3 Share sg21
hares -modify share_${dg3}_r10_1_$dg3 PathName "/autotcdir/ITF_5_${dg3}_r10_1"
hares -modify share_${dg3}_r10_1_$dg3 Options "rw,root=@10.200.0.0/8"
hares -modify share_${dg3}_r10_1_$dg3 Enabled 1
hares -add vol_${dg3}_r0_2_$dg3 Volume sg21
hares -modify vol_${dg3}_r0_2_$dg3 DiskGroup $dg3
hares -modify vol_${dg3}_r0_2_$dg3 Volume ${dg3}_r0_2
hares -modify vol_${dg3}_r0_2_$dg3 Enabled 1
hares -add vol_${dg3}_r10_1_$dg3 Volume sg21
hares -modify vol_${dg3}_r10_1_$dg3 DiskGroup $dg3
hares -modify vol_${dg3}_r10_1_$dg3 Volume ${dg3}_r10_1
hares -modify vol_${dg3}_r10_1_$dg3 Enabled 1
hares -link ip_$node1 nic_sg12_$nic
hares -link ip_$node1 share_${dg2}_r0_2_$dg2
hares -link ip_$node1 share_${dg2}_r10_1_$dg2
hares -link mnt_${dg2}_r0_2_$dg2 vol_${dg2}_r0_2_$dg2
hares -link mnt_${dg2}_r10_1_$dg2 vol_${dg2}_r10_1_$dg2
hares -link nfsres_sg12 ip_$node1
hares -link nfsres_sg12_l mnt_${dg2}_r0_2_$dg2
hares -link nfsres_sg12_l mnt_${dg2}_r10_1_$dg2
hares -link share_${dg2}_r0_2_$dg2 nfsres_sg12_l
hares -link share_${dg2}_r0_2_$dg2 proxy_sg12
hares -link share_${dg2}_r10_1_$dg2 nfsres_sg12_l
hares -link share_${dg2}_r10_1_$dg2 proxy_sg12
hares -link vol_${dg2}_r0_2_$dg2 ${dg2}_sg12
hares -link vol_${dg2}_r10_1_$dg2 ${dg2}_sg12
hares -link ip_$node2 nic_sg21_$nic
hares -link ip_$node2 share_${dg3}_r0_2_$dg3
hares -link ip_$node2 share_${dg3}_r10_1_$dg3
hares -link mnt_${dg3}_r0_2_$dg3 vol_${dg3}_r0_2_$dg3
hares -link mnt_${dg3}_r10_1_$dg3 vol_${dg3}_r10_1_$dg3
hares -link nfsres_sg21 ip_$node2
hares -link nfsres_sg21_l mnt_${dg3}_r0_2_$dg3
hares -link nfsres_sg21_l mnt_${dg3}_r10_1_$dg3
hares -link share_${dg3}_r0_2_$dg3 nfsres_sg21_l
hares -link share_${dg3}_r0_2_$dg3 proxy_sg21
hares -link share_${dg3}_r10_1_$dg3 nfsres_sg21_l
hares -link share_${dg3}_r10_1_$dg3 proxy_sg21
hares -link vol_${dg3}_r0_2_$dg3 ${dg1}_sg21
hares -link vol_${dg3}_r10_1_$dg3 ${dg1}_sg21
EOF
}
genRacHaSgconfLinux(){
#DES:Generate mix service group config for main.cf
local node1 node2 node1nic node2nic vip1 vip2 nic mask gw
args=($*)
node1=${args[0]}
node2=${args[1]}
node1nic=${args[2]}
node2nic=${args[3]}
nic=${args[4]}
vip1=${args[5]}
vip2=${args[6]}
mask=${args[7]}
gw=${args[8]}
dg1=autotcdg1
dg2=autotcdg2
dg3=autotcdg3
cat << EOF
hagrp -add nfs_sg
hagrp -modify nfs_sg SystemList  $node1 0 $node2 1
hagrp -modify nfs_sg AutoFailOver 0
hagrp -modify nfs_sg Parallel 1
hagrp -modify nfs_sg AutoStartList  $node1 $node2
hagrp -modify nfs_sg SourceFile "./main.cf"
hares -add n1 NFS nfs_sg
hares -modify n1 Nproc 8
hares -modify n1 GracePeriod 90
hares -modify n1 NFSSecurity 0
hares -modify n1 NFSv4Support 0
hares -modify n1 LockFileTimeout 180
hares -modify n1 Enabled 1
hares -add ph1 Phantom nfs_sg
hares -modify ph1 Enabled 1
hagrp -add sg12
hagrp -modify sg12 SystemList  $node1 0 $node2 2
hagrp -modify sg12 AutoStartList  $node1
hagrp -modify sg12 SourceFile "./main.cf"
hares -add ${dg2}_sg12 DiskGroup sg12
hares -modify ${dg2}_sg12 DiskGroup $dg2
hares -modify ${dg2}_sg12 StartVolumes 0
hares -modify ${dg2}_sg12 StopVolumes 0
hares -modify ${dg2}_sg12 MonitorReservation 0
hares -modify ${dg2}_sg12 tempUseFence INVALID
hares -modify ${dg2}_sg12 Reservation ClusterDefault
hares -modify ${dg2}_sg12 ClearClone 0
hares -modify ${dg2}_sg12 Enabled 1
hares -add ip_$node1 IP sg12
hares -local ip_$node1 Device
hares -modify ip_$node1 Device $node1nic -sys $node1
hares -modify ip_$node1 Device $node2nic -sys $node2
hares -modify ip_$node1 Address "$vip1"
hares -modify ip_$node1 NetMask "$mask"
hares -modify ip_$node1 PrefixLen 1000
hares -modify ip_$node1 Enabled 1
hares -add mnt_${dg2}_r0_2_$dg2 Mount sg12
hares -modify mnt_${dg2}_r0_2_$dg2 MountPoint "/autotcdir/ITF_3_${dg2}_r0_2"
hares -modify mnt_${dg2}_r0_2_$dg2 BlockDevice "/dev/vx/dsk/$dg2/${dg2}_r0_2"
hares -modify mnt_${dg2}_r0_2_$dg2 FSType vxfs
hares -modify mnt_${dg2}_r0_2_$dg2 MountOpt largefiles
hares -modify mnt_${dg2}_r0_2_$dg2 FsckOpt "%-y"
hares -modify mnt_${dg2}_r0_2_$dg2 SnapUmount 0
hares -modify mnt_${dg2}_r0_2_$dg2 CkptUmount 1
hares -modify mnt_${dg2}_r0_2_$dg2 RecursiveMnt 0
hares -modify mnt_${dg2}_r0_2_$dg2 VxFSMountLock 1
hares -modify mnt_${dg2}_r0_2_$dg2 Enabled 1
hares -add mnt_${dg2}_r10_1_$dg2 Mount sg12
hares -modify mnt_${dg2}_r10_1_$dg2 MountPoint "/autotcdir/ITF_1_${dg2}_r10_1"
hares -modify mnt_${dg2}_r10_1_$dg2 BlockDevice "/dev/vx/dsk/$dg2/${dg2}_r10_1"
hares -modify mnt_${dg2}_r10_1_$dg2 FSType vxfs
hares -modify mnt_${dg2}_r10_1_$dg2 MountOpt largefiles
hares -modify mnt_${dg2}_r10_1_$dg2 FsckOpt "%-y"
hares -modify mnt_${dg2}_r10_1_$dg2 SnapUmount 0
hares -modify mnt_${dg2}_r10_1_$dg2 CkptUmount 1
hares -modify mnt_${dg2}_r10_1_$dg2 RecursiveMnt 0
hares -modify mnt_${dg2}_r10_1_$dg2 VxFSMountLock 1
hares -modify mnt_${dg2}_r10_1_$dg2 Enabled 1
hares -add nfsres_sg12 NFSRestart sg12
hares -modify nfsres_sg12 NFSRes n1
hares -modify nfsres_sg12 LocksPathName "/autotcdir/ITF_1_${dg2}_r10_1"
hares -modify nfsres_sg12 NFSLockFailover 1
hares -modify nfsres_sg12 Enabled 1
hares -add nfsres_sg12_l NFSRestart sg12
hares -modify nfsres_sg12_l NFSRes n1
hares -modify nfsres_sg12_l Lower 1
hares -modify nfsres_sg12_l LocksPathName "/autotcdir/ITF_1_${dg2}_r10_1"
hares -modify nfsres_sg12_l NFSLockFailover 1
hares -modify nfsres_sg12_l Enabled 1
hares -add nic_sg12_$nic NIC sg12
hares -local nic_sg12_$nic Device
hares -modify nic_sg12_$nic Device $node1nic -sys $node1
hares -modify nic_sg12_$nic Device $node2nic -sys $node2
hares -modify nic_sg12_$nic NetworkHosts  "$gw"
hares -modify nic_sg12_$nic PingOptimize 1
hares -modify nic_sg12_$nic Mii 1
hares -modify nic_sg12_$nic Enabled 1
hares -add proxy_sg12 Proxy sg12
hares -modify proxy_sg12 TargetResName n1
hares -modify proxy_sg12 Enabled 1
hares -add share_${dg2}_r0_2_$dg2 Share sg12
hares -modify share_${dg2}_r0_2_$dg2 PathName "/autotcdir/ITF_3_${dg2}_r0_2"
hares -modify share_${dg2}_r0_2_$dg2 Options "rw,no_root_squash"
hares -modify share_${dg2}_r0_2_$dg2 OtherClients -delete -keys
hares -modify share_${dg2}_r0_2_$dg2 Enabled 1
hares -add share_${dg2}_r10_1_$dg2 Share sg12
hares -modify share_${dg2}_r10_1_$dg2 PathName "/autotcdir/ITF_1_${dg2}_r10_1"
hares -modify share_${dg2}_r10_1_$dg2 Options "rw,no_root_squash"
hares -modify share_${dg2}_r10_1_$dg2 OtherClients -delete -keys
hares -modify share_${dg2}_r10_1_$dg2 Enabled 1
hares -add vol_${dg2}_r0_2_$dg2 Volume sg12
hares -modify vol_${dg2}_r0_2_$dg2 DiskGroup $dg2
hares -modify vol_${dg2}_r0_2_$dg2 Volume ${dg2}_r0_2
hares -modify vol_${dg2}_r0_2_$dg2 Enabled 1
hares -add vol_${dg2}_r10_1_$dg2 Volume sg12
hares -modify vol_${dg2}_r10_1_$dg2 DiskGroup $dg2
hares -modify vol_${dg2}_r10_1_$dg2 Volume ${dg2}_r10_1
hares -modify vol_${dg2}_r10_1_$dg2 Enabled 1
hagrp -add sg21
hagrp -modify sg21 SystemList  $node2 0 $node1 1
hagrp -modify sg21 AutoStartList  $node2
hagrp -modify sg21 SourceFile "./main.cf"
hares -add ${dg1}_sg21 DiskGroup sg21
hares -modify ${dg1}_sg21 DiskGroup $dg3
hares -modify ${dg1}_sg21 StartVolumes 0
hares -modify ${dg1}_sg21 StopVolumes 0
hares -modify ${dg1}_sg21 MonitorReservation 0
hares -modify ${dg1}_sg21 tempUseFence INVALID
hares -modify ${dg1}_sg21 Reservation ClusterDefault
hares -modify ${dg1}_sg21 ClearClone 0
hares -modify ${dg1}_sg21 Enabled 1
hares -add ip_$node2 IP sg21
hares -local ip_$node2 Device
hares -modify ip_$node2 Device $node1nic -sys $node2
hares -modify ip_$node2 Device $node2nic -sys $node1
hares -modify ip_$node2 Address "$vip2"
hares -modify ip_$node2 NetMask "$mask"
hares -modify ip_$node2 PrefixLen 1000
hares -modify ip_$node2 Enabled 1
hares -add mnt_${dg3}_r0_2_$dg3 Mount sg21
hares -modify mnt_${dg3}_r0_2_$dg3 MountPoint "/autotcdir/ITF_6_${dg3}_r0_2"
hares -modify mnt_${dg3}_r0_2_$dg3 BlockDevice "/dev/vx/dsk/$dg3/${dg3}_r0_2"
hares -modify mnt_${dg3}_r0_2_$dg3 FSType vxfs
hares -modify mnt_${dg3}_r0_2_$dg3 MountOpt largefiles
hares -modify mnt_${dg3}_r0_2_$dg3 FsckOpt "%-y"
hares -modify mnt_${dg3}_r0_2_$dg3 SnapUmount 0
hares -modify mnt_${dg3}_r0_2_$dg3 CkptUmount 1
hares -modify mnt_${dg3}_r0_2_$dg3 RecursiveMnt 0
hares -modify mnt_${dg3}_r0_2_$dg3 VxFSMountLock 1
hares -modify mnt_${dg3}_r0_2_$dg3 Enabled 1
hares -add mnt_${dg3}_r10_1_$dg3 Mount sg21
hares -modify mnt_${dg3}_r10_1_$dg3 MountPoint "/autotcdir/ITF_5_${dg3}_r10_1"
hares -modify mnt_${dg3}_r10_1_$dg3 BlockDevice "/dev/vx/dsk/$dg3/${dg3}_r10_1"
hares -modify mnt_${dg3}_r10_1_$dg3 FSType vxfs
hares -modify mnt_${dg3}_r10_1_$dg3 MountOpt largefiles
hares -modify mnt_${dg3}_r10_1_$dg3 FsckOpt "%-y"
hares -modify mnt_${dg3}_r10_1_$dg3 SnapUmount 0
hares -modify mnt_${dg3}_r10_1_$dg3 CkptUmount 1
hares -modify mnt_${dg3}_r10_1_$dg3 RecursiveMnt 0
hares -modify mnt_${dg3}_r10_1_$dg3 VxFSMountLock 1
hares -modify mnt_${dg3}_r10_1_$dg3 Enabled 1
hares -add nfsres_sg21 NFSRestart sg21
hares -modify nfsres_sg21 NFSRes n1
hares -modify nfsres_sg21 LocksPathName "/autotcdir/ITF_5_${dg3}_r10_1"
hares -modify nfsres_sg21 NFSLockFailover 1
hares -modify nfsres_sg21 Enabled 1
hares -add nfsres_sg21_l NFSRestart sg21
hares -modify nfsres_sg21_l NFSRes n1
hares -modify nfsres_sg21_l Lower 1
hares -modify nfsres_sg21_l LocksPathName "/autotcdir/ITF_5_${dg3}_r10_1"
hares -modify nfsres_sg21_l NFSLockFailover 1
hares -modify nfsres_sg21_l Enabled 1
hares -add nic_sg21_$nic NIC sg21
hares -local nic_sg21_$nic Device
hares -modify nic_sg21_$nic Device $node1nic -sys $node2
hares -modify nic_sg21_$nic Device $node2nic -sys $node1
hares -modify nic_sg21_$nic NetworkHosts  "$gw"
hares -modify nic_sg21_$nic PingOptimize 1
hares -modify nic_sg21_$nic Mii 1
hares -modify nic_sg21_$nic Enabled 1
hares -add proxy_sg21 Proxy sg21
hares -modify proxy_sg21 TargetResName n1
hares -modify proxy_sg21 Enabled 1
hares -add share_${dg3}_r0_2_$dg3 Share sg21
hares -modify share_${dg3}_r0_2_$dg3 PathName "/autotcdir/ITF_6_${dg3}_r0_2"
hares -modify share_${dg3}_r0_2_$dg3 Options "rw,no_root_squash"
hares -modify share_${dg3}_r0_2_$dg3 OtherClients -delete -keys
hares -modify share_${dg3}_r0_2_$dg3 Enabled 1
hares -add share_${dg3}_r10_1_$dg3 Share sg21
hares -modify share_${dg3}_r10_1_$dg3 PathName "/autotcdir/ITF_5_${dg3}_r10_1"
hares -modify share_${dg3}_r10_1_$dg3 Options "rw,no_root_squash"
hares -modify share_${dg3}_r10_1_$dg3 OtherClients -delete -keys
hares -modify share_${dg3}_r10_1_$dg3 Enabled 1
hares -add vol_${dg3}_r0_2_$dg3 Volume sg21
hares -modify vol_${dg3}_r0_2_$dg3 DiskGroup $dg3
hares -modify vol_${dg3}_r0_2_$dg3 Volume ${dg3}_r0_2
hares -modify vol_${dg3}_r0_2_$dg3 Enabled 1
hares -add vol_${dg3}_r10_1_$dg3 Volume sg21
hares -modify vol_${dg3}_r10_1_$dg3 DiskGroup $dg3
hares -modify vol_${dg3}_r10_1_$dg3 Volume ${dg3}_r10_1
hares -modify vol_${dg3}_r10_1_$dg3 Enabled 1
hares -link ip_$node1 nic_sg12_$nic
hares -link ip_$node1 share_${dg2}_r0_2_$dg2
hares -link ip_$node1 share_${dg2}_r10_1_$dg2
hares -link mnt_${dg2}_r0_2_$dg2 vol_${dg2}_r0_2_$dg2
hares -link mnt_${dg2}_r10_1_$dg2 vol_${dg2}_r10_1_$dg2
hares -link nfsres_sg12 ip_$node1
hares -link nfsres_sg12_l mnt_${dg2}_r0_2_$dg2
hares -link nfsres_sg12_l mnt_${dg2}_r10_1_$dg2
hares -link share_${dg2}_r0_2_$dg2 nfsres_sg12_l
hares -link share_${dg2}_r0_2_$dg2 proxy_sg12
hares -link share_${dg2}_r10_1_$dg2 nfsres_sg12_l
hares -link share_${dg2}_r10_1_$dg2 proxy_sg12
hares -link vol_${dg2}_r0_2_$dg2 ${dg2}_sg12
hares -link vol_${dg2}_r10_1_$dg2 ${dg2}_sg12
hares -link ip_$node2 nic_sg21_$nic
hares -link ip_$node2 share_${dg3}_r0_2_$dg3
hares -link ip_$node2 share_${dg3}_r10_1_$dg3
hares -link mnt_${dg3}_r0_2_$dg3 vol_${dg3}_r0_2_$dg3
hares -link mnt_${dg3}_r10_1_$dg3 vol_${dg3}_r10_1_$dg3
hares -link nfsres_sg21 ip_$node2
hares -link nfsres_sg21_l mnt_${dg3}_r0_2_$dg3
hares -link nfsres_sg21_l mnt_${dg3}_r10_1_$dg3
hares -link share_${dg3}_r0_2_$dg3 nfsres_sg21_l
hares -link share_${dg3}_r0_2_$dg3 proxy_sg21
hares -link share_${dg3}_r10_1_$dg3 nfsres_sg21_l
hares -link share_${dg3}_r10_1_$dg3 proxy_sg21
hares -link vol_${dg3}_r0_2_$dg3 ${dg1}_sg21
hares -link vol_${dg3}_r10_1_$dg3 ${dg1}_sg21
EOF
}

genRacHaSgconfSolaris(){
#DES:Generate mix service group config for main.cf
local node1 node2 node1nic node2nic vip1 vip2 nic mask gw
args=($*)
node1=${args[0]}
node2=${args[1]}
node1nic=${args[2]}
node2nic=${args[3]}
nic=${args[4]}
vip1=${args[5]}
vip2=${args[6]}
mask=${args[7]}
gw=${args[8]}
dg1=autotcdg1
dg2=autotcdg2
dg3=autotcdg3
cat << EOF
hagrp -add nfs_sg
hagrp -modify nfs_sg SystemList  $node1 0 $node2 1
hagrp -modify nfs_sg AutoFailOver 0
hagrp -modify nfs_sg Parallel 1
hagrp -modify nfs_sg AutoStartList  $node1 $node2
hagrp -modify nfs_sg SourceFile "./main.cf"
hares -add n1 NFS nfs_sg
hares -modify n1 Nservers 6
hares -modify n1 UseSMF 1
hares -modify n1 LockFileTimeout 180
hares -modify n1 CleanRmtab 0
hares -modify n1 Protocol all
hares -modify n1 Enabled 1
hares -add ph1 Phantom nfs_sg
hares -modify ph1 Enabled 1
hagrp -add sg12
hagrp -modify sg12 SystemList  $node1 0 $node2 2
hagrp -modify sg12 AutoStartList  $node1
hagrp -modify sg12 SourceFile "./main.cf"
hares -add ${dg2}_sg12 DiskGroup sg12
hares -modify ${dg2}_sg12 DiskGroup $dg2
hares -modify ${dg2}_sg12 StartVolumes 0
hares -modify ${dg2}_sg12 StopVolumes 0
hares -modify ${dg2}_sg12 MonitorReservation 0
hares -modify ${dg2}_sg12 tempUseFence INVALID
hares -modify ${dg2}_sg12 Reservation ClusterDefault
hares -modify ${dg2}_sg12 ClearClone 0
hares -modify ${dg2}_sg12 Enabled 1
hares -add ip_$node1 IP sg12
hares -local ip_$node1 Device
hares -modify ip_$node1 Device $node1nic -sys $node1
hares -modify ip_$node1 Device $node2nic -sys $node2
hares -modify ip_$node1 Address "$vip1"
hares -modify ip_$node1 NetMask "$mask"
hares -modify ip_$node1 IpadmIfProperties -delete -keys
hares -modify ip_$node1 IpadmAddrProperties -delete -keys
hares -modify ip_$node1 ArpDelay 1
hares -modify ip_$node1 ExclusiveIPZone 0
hares -modify ip_$node1 Enabled 1
hares -add mnt_${dg2}_r0_2_$dg2 Mount sg12
hares -modify mnt_${dg2}_r0_2_$dg2 MountPoint "/autotcdir/ITF_3_${dg2}_r0_2"
hares -modify mnt_${dg2}_r0_2_$dg2 BlockDevice "/dev/vx/dsk/$dg2/${dg2}_r0_2"
hares -modify mnt_${dg2}_r0_2_$dg2 FSType vxfs
hares -modify mnt_${dg2}_r0_2_$dg2 MountOpt largefiles
hares -modify mnt_${dg2}_r0_2_$dg2 FsckOpt "%-y"
hares -modify mnt_${dg2}_r0_2_$dg2 CkptUmount 1
hares -modify mnt_${dg2}_r0_2_$dg2 RecursiveMnt 0
hares -modify mnt_${dg2}_r0_2_$dg2 VxFSMountLock 1
hares -modify mnt_${dg2}_r0_2_$dg2 Enabled 1
hares -add mnt_${dg2}_r10_1_$dg2 Mount sg12
hares -modify mnt_${dg2}_r10_1_$dg2 MountPoint "/autotcdir/ITF_1_${dg2}_r10_1"
hares -modify mnt_${dg2}_r10_1_$dg2 BlockDevice "/dev/vx/dsk/$dg2/${dg2}_r10_1"
hares -modify mnt_${dg2}_r10_1_$dg2 FSType vxfs
hares -modify mnt_${dg2}_r10_1_$dg2 MountOpt largefiles
hares -modify mnt_${dg2}_r10_1_$dg2 FsckOpt "%-y"
hares -modify mnt_${dg2}_r10_1_$dg2 CkptUmount 1
hares -modify mnt_${dg2}_r10_1_$dg2 RecursiveMnt 0
hares -modify mnt_${dg2}_r10_1_$dg2 VxFSMountLock 1
hares -modify mnt_${dg2}_r10_1_$dg2 CacheRestoreAccess 0
hares -modify mnt_${dg2}_r10_1_$dg2 Enabled 1
hares -add nfsres_sg12 NFSRestart sg12
hares -modify nfsres_sg12 NFSRes n1
hares -modify nfsres_sg12 LocksPathName "/autotcdir/ITF_1_${dg2}_r10_1"
hares -modify nfsres_sg12 NFSLockFailover 1
hares -modify nfsres_sg12 LockServers 20
hares -modify nfsres_sg12 Enabled 1
hares -add nfsres_sg12_l NFSRestart sg12
hares -modify nfsres_sg12_l NFSRes n1
hares -modify nfsres_sg12_l Lower 1
hares -modify nfsres_sg12_l LocksPathName "/autotcdir/ITF_1_${dg2}_r10_1"
hares -modify nfsres_sg12_l NFSLockFailover 1
hares -modify nfsres_sg12_l LockServers 20
hares -modify nfsres_sg12_l Enabled 1
hares -add nic_sg12_$nic NIC sg12
hares -local nic_sg12_$nic Device
hares -modify nic_sg12_$nic Device $node1nic -sys $node1
hares -modify nic_sg12_$nic Device $node2nic -sys $node2
hares -modify nic_sg12_$nic NetworkHosts  "$gw"
hares -modify nic_sg12_$nic NetworkType ether
hares -modify nic_sg12_$nic PingOptimize 1
hares -modify nic_sg12_$nic Protocol IPv4
hares -modify nic_sg12_$nic Enabled 1
hares -modify nic_sg12_$nic ExclusiveIPZone 0
hares -add share_${dg2}_r0_2_$dg2 Share sg12
hares -modify share_${dg2}_r0_2_$dg2 PathName "/autotcdir/ITF_3_${dg2}_r0_2"
hares -modify share_${dg2}_r0_2_$dg2 Options "rw,root=@10.200.0.0/8"
hares -modify share_${dg2}_r0_2_$dg2 Enabled 1
hares -add share_${dg2}_r10_1_$dg2 Share sg12
hares -modify share_${dg2}_r10_1_$dg2 PathName "/autotcdir/ITF_1_${dg2}_r10_1"
hares -modify share_${dg2}_r10_1_$dg2 Options "rw,root=@10.200.0.0/8"
hares -modify share_${dg2}_r10_1_$dg2 Enabled 1
hares -add vol_${dg2}_r0_2_$dg2 Volume sg12
hares -modify vol_${dg2}_r0_2_$dg2 DiskGroup $dg2
hares -modify vol_${dg2}_r0_2_$dg2 Volume ${dg2}_r0_2
hares -modify vol_${dg2}_r0_2_$dg2 Enabled 1
hares -add vol_${dg2}_r10_1_$dg2 Volume sg12
hares -modify vol_${dg2}_r10_1_$dg2 DiskGroup $dg2
hares -modify vol_${dg2}_r10_1_$dg2 Volume ${dg2}_r10_1
hares -modify vol_${dg2}_r10_1_$dg2 Enabled 1
hagrp -add sg21
hagrp -modify sg21 SystemList  $node2 0 $node1 1
hagrp -modify sg21 AutoStartList  $node2
hagrp -modify sg21 SourceFile "./main.cf"
hares -add ${dg1}_sg21 DiskGroup sg21
hares -modify ${dg1}_sg21 DiskGroup $dg3
hares -modify ${dg1}_sg21 StartVolumes 0
hares -modify ${dg1}_sg21 StopVolumes 0
hares -modify ${dg1}_sg21 MonitorReservation 0
hares -modify ${dg1}_sg21 tempUseFence INVALID
hares -modify ${dg1}_sg21 Reservation ClusterDefault
hares -modify ${dg1}_sg21 ClearClone 0
hares -modify ${dg1}_sg21 Enabled 1
hares -add ip_$node2 IP sg21
hares -local ip_$node2 Device
hares -modify ip_$node2 Device $node1nic -sys $node2
hares -modify ip_$node2 Device $node2nic -sys $node1
hares -modify ip_$node2 Address "$vip2"
hares -modify ip_$node2 NetMask "$mask"
hares -modify ip_$node2 IpadmIfProperties -delete -keys
hares -modify ip_$node2 IpadmAddrProperties -delete -keys
hares -modify ip_$node2 ArpDelay 1
hares -modify ip_$node2 ExclusiveIPZone 0
hares -modify ip_$node2 Enabled 1
hares -add mnt_${dg3}_r0_2_$dg3 Mount sg21
hares -modify mnt_${dg3}_r0_2_$dg3 MountPoint "/autotcdir/ITF_6_${dg3}_r0_2"
hares -modify mnt_${dg3}_r0_2_$dg3 BlockDevice "/dev/vx/dsk/$dg3/${dg3}_r0_2"
hares -modify mnt_${dg3}_r0_2_$dg3 FSType vxfs
hares -modify mnt_${dg3}_r0_2_$dg3 MountOpt largefiles
hares -modify mnt_${dg3}_r0_2_$dg3 FsckOpt "%-y"
hares -modify mnt_${dg3}_r0_2_$dg3 CkptUmount 1
hares -modify mnt_${dg3}_r0_2_$dg3 RecursiveMnt 0
hares -modify mnt_${dg3}_r0_2_$dg3 VxFSMountLock 1
hares -modify mnt_${dg3}_r0_2_$dg3 CacheRestoreAccess 0
hares -modify mnt_${dg3}_r0_2_$dg3 Enabled 1
hares -add mnt_${dg3}_r10_1_$dg3 Mount sg21
hares -modify mnt_${dg3}_r10_1_$dg3 MountPoint "/autotcdir/ITF_5_${dg3}_r10_1"
hares -modify mnt_${dg3}_r10_1_$dg3 BlockDevice "/dev/vx/dsk/$dg3/${dg3}_r10_1"
hares -modify mnt_${dg3}_r10_1_$dg3 FSType vxfs
hares -modify mnt_${dg3}_r10_1_$dg3 MountOpt largefiles
hares -modify mnt_${dg3}_r10_1_$dg3 FsckOpt "%-y"
hares -modify mnt_${dg3}_r10_1_$dg3 CkptUmount 1
hares -modify mnt_${dg3}_r10_1_$dg3 RecursiveMnt 0
hares -modify mnt_${dg3}_r10_1_$dg3 VxFSMountLock 1
hares -modify mnt_${dg3}_r10_1_$dg3 CacheRestoreAccess 0
hares -modify mnt_${dg3}_r10_1_$dg3 Enabled 1
hares -add nfsres_sg21 NFSRestart sg21
hares -modify nfsres_sg21 NFSRes n1
hares -modify nfsres_sg21 LocksPathName "/autotcdir/ITF_5_${dg3}_r10_1"
hares -modify nfsres_sg21 NFSLockFailover 1
hares -modify nfsres_sg21 LockServers 20
hares -modify nfsres_sg21 Enabled 1
hares -add nfsres_sg21_l NFSRestart sg21
hares -modify nfsres_sg21_l NFSRes n1
hares -modify nfsres_sg21_l Lower 1
hares -modify nfsres_sg21_l LocksPathName "/autotcdir/ITF_5_${dg3}_r10_1"
hares -modify nfsres_sg21_l NFSLockFailover 1
hares -modify nfsres_sg21_l LockServers 20
hares -modify nfsres_sg21_l Enabled 1
hares -add nic_sg21_$nic NIC sg21
hares -local nic_sg21_$nic Device
hares -modify nic_sg21_$nic Device $node1nic -sys $node2
hares -modify nic_sg21_$nic Device $node2nic -sys $node1
hares -modify nic_sg21_$nic NetworkHosts  "$gw"
hares -modify nic_sg21_$nic NetworkType ether
hares -modify nic_sg21_$nic PingOptimize 1
hares -modify nic_sg21_$nic Protocol IPv4
hares -modify nic_sg21_$nic ExclusiveIPZone 0
hares -modify nic_sg21_$nic Enabled 1
hares -add share_${dg3}_r0_2_$dg3 Share sg21
hares -modify share_${dg3}_r0_2_$dg3 PathName "/autotcdir/ITF_6_${dg3}_r0_2"
hares -modify share_${dg3}_r0_2_$dg3 Options "rw,root=@10.200.0.0/8"
hares -modify share_${dg3}_r0_2_$dg3 Enabled 1
hares -add share_${dg3}_r10_1_$dg3 Share sg21
hares -modify share_${dg3}_r10_1_$dg3 PathName "/autotcdir/ITF_5_${dg3}_r10_1"
hares -modify share_${dg3}_r10_1_$dg3 Options "rw,root=@10.200.0.0/8"
hares -modify share_${dg3}_r10_1_$dg3 Enabled 1
hares -add vol_${dg3}_r0_2_$dg3 Volume sg21
hares -modify vol_${dg3}_r0_2_$dg3 DiskGroup $dg3
hares -modify vol_${dg3}_r0_2_$dg3 Volume ${dg3}_r0_2
hares -modify vol_${dg3}_r0_2_$dg3 Enabled 1
hares -add vol_${dg3}_r10_1_$dg3 Volume sg21
hares -modify vol_${dg3}_r10_1_$dg3 DiskGroup $dg3
hares -modify vol_${dg3}_r10_1_$dg3 Volume ${dg3}_r10_1
hares -modify vol_${dg3}_r10_1_$dg3 Enabled 1
hares -link ip_$node1 nic_sg12_$nic
hares -link ip_$node1 share_${dg2}_r0_2_$dg2
hares -link ip_$node1 share_${dg2}_r10_1_$dg2
hares -link mnt_${dg2}_r0_2_$dg2 vol_${dg2}_r0_2_$dg2
hares -link mnt_${dg2}_r10_1_$dg2 vol_${dg2}_r10_1_$dg2
hares -link nfsres_sg12 ip_$node1
hares -link nfsres_sg12_l mnt_${dg2}_r0_2_$dg2
hares -link nfsres_sg12_l mnt_${dg2}_r10_1_$dg2
hares -link share_${dg2}_r0_2_$dg2 nfsres_sg12_l
hares -link share_${dg2}_r10_1_$dg2 nfsres_sg12_l
hares -link vol_${dg2}_r0_2_$dg2 ${dg2}_sg12
hares -link vol_${dg2}_r10_1_$dg2 ${dg2}_sg12
hares -link ip_$node2 nic_sg21_$nic
hares -link ip_$node2 share_${dg3}_r0_2_$dg3
hares -link ip_$node2 share_${dg3}_r10_1_$dg3
hares -link mnt_${dg3}_r0_2_$dg3 vol_${dg3}_r0_2_$dg3
hares -link mnt_${dg3}_r10_1_$dg3 vol_${dg3}_r10_1_$dg3
hares -link nfsres_sg21 ip_$node2
hares -link nfsres_sg21_l mnt_${dg3}_r0_2_$dg3
hares -link nfsres_sg21_l mnt_${dg3}_r10_1_$dg3
hares -link share_${dg3}_r0_2_$dg3 nfsres_sg21_l
hares -link share_${dg3}_r10_1_$dg3 nfsres_sg21_l
hares -link vol_${dg3}_r0_2_$dg3 ${dg1}_sg21
hares -link vol_${dg3}_r10_1_$dg3 ${dg1}_sg21
EOF
}
