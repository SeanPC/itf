#!/bin/bash
clearSgFault(){
#DES:clear the fault properties for the service group
local sg
sg=$1
oLog des "Clear the fault properties for service group $sg"
RExec root $NODE1 "/opt/VRTS/bin/hagrp -state $sg"
if echo "$out"|grep FAULTED > /dev/null 2>&1
then
	RExec root $NODE1 "/opt/VRTS/bin/hagrp -clear $sg"
else
	return 0
fi
}
switchGroup(){
#DES:Switch service group to the node 
local node group begin
node=$1
group=$2
oLog "des" "Switch Group $group to $node"
RExec root $node "cat $autotcengineA|wc -l|awk '{print \$1}'"
begin=$[$out+1]
RExec root $node "/opt/VRTS/bin/hagrp -switch $group -to $node"
sleep 10
for i in `seq 60`
do
	RExec root $node "/opt/VRTSvcs/bin/hagrp -state $group -sys $node"
	[ "$out" = ONLINE ] && break
        sleep 10
done
RExec root $node "noexit:/opt/VRTSvcs/bin/hagrp -state $group -sys $node" 'ONLINE' 'part|start'
if [ "$result" != Passed ]
then
        RExec root $node "sed -n $begin,'$'p $autotcengineA"
	oLog error "Failed to switch group $group to $node"
        myexit 1
fi
}
startGroup(){
#DES:Start service group on the node
local node group i file begin
node=$1
group=$2
oLog "des" "Online Group $group on $node" 
RExec root $node "cat $autotcengineA|wc -l|awk '{print \$1}'"
begin=$[$out+1]
RExec root $node "/opt/VRTSvcs/bin/hagrp -online $group -sys $node"
sleep 10
for i in `seq 60`
do
	RExec root $node "/opt/VRTSvcs/bin/hagrp -state $group -sys $node"
	[ "$out" = ONLINE ] && break
	sleep 10
done
RExec root $node "noexit:/opt/VRTSvcs/bin/hagrp -state $group -sys $node" 'ONLINE' 'part|start'
if [ "$result" != Passed ]
then
	RExec root $node "sed -n $begin,'$'p $autotcengineA"
	oLog error "Failed to start group $group"
	myexit 1
fi
}

startGroupAny(){
#DES:Start service group on any node,Only for Parallel service group
local node group i file begin
node=$1
group=$2
oLog "des" "Online Group $group on all active nodes"
if [ -z "$node_count" ] 
then
	RExec root $node "/opt/VRTSvcs/bin/hasys -state"
	node_count=`echo "$out"|grep RUNNING|wc -l`
fi
RExec root $node "cat $autotcengineA|wc -l|awk '{print \$1}'"
begin=$[$out+1]
RExec root $node "/opt/VRTSvcs/bin/hagrp -online $group -any"
sleep 10
for i in `seq 60`
do
        RExec root $node "/opt/VRTSvcs/bin/hagrp -state $group"
	out=`echo "$out"|grep ^$group|grep ONLINE|wc -l`
        [ "$out" = "$node_count" ] && break
        sleep 10
done
RExec root $node "/opt/VRTSvcs/bin/hagrp -state $group"
out=`echo "$out"|grep ^$group|grep ONLINE|wc -l`
if [ "$out" != "$node_count" ]
then
        RExec root $node "sed -n $begin,'$'p $autotcengineA"
	oLog error "Failed to start group $group"
        myexit 1
fi
}

stopGroup(){
#DES:Stop service group on the node
local node group i file begin
node=$1
group=$2
oLog "des" "Offline Group $group on $node"
RExec root $node "cat $autotcengineA|wc -l|awk '{print \$1}'"
begin=$[$out+1]
RExec root $node "/opt/VRTSvcs/bin/hagrp -offline $group -sys $node"
sleep 10
for i in `seq 60`
do
        RExec root $node "/opt/VRTSvcs/bin/hagrp -state $group -sys $node"
        [ "$out" = OFFLINE ] && break
        sleep 10
done
RExec root $node "noexit:/opt/VRTSvcs/bin/hagrp -state $group -sys $node" 'OFFLINE' 'part|stop'
if [ "$result" != Passed ]
then
        RExec root $node "sed -n $begin,'$'p $autotcengineA"
	oLog error "Failed to stop group $group"
        myexit 1
fi
}

stopGroupAny(){
#DES:Stop service group on any node,Only for Parallel service group
local node group i file begin
node=$1
group=$2
oLog "des" "Offline Group $group on all active nodes"
if [ -z "$node_count" ]
then
        RExec root $node "/opt/VRTSvcs/bin/hasys -state"
        node_count=`echo "$out"|grep RUNNING|wc -l`
fi
RExec root $node "cat $autotcengineA|wc -l|awk '{print \$1}'"
begin=$[$out+1]
RExec root $node "/opt/VRTSvcs/bin/hagrp -offline $group -any"
sleep 10
for i in `seq 60`
do
        RExec root $node "/opt/VRTSvcs/bin/hagrp -state $group"
	out=`echo "$out"|grep ^$group|grep OFFLINE|wc -l`
        [ "$out" = "$node_count" ] && break
        sleep 10
done
RExec root $node "noexit:/opt/VRTSvcs/bin/hagrp -state $group"
out=`echo "$out"|grep ^$group|grep OFFLINE|wc -l`
if [ "$out" != "$node_count" ]
then
        RExec root $node "sed -n $begin,'$'p $autotcengineA"
	oLog error "Failed to stop group $group"
        myexit 1
fi
}

checkGroupStatus(){
#DES:check group status,retcode(0,ONLINE;1,Partly ONLINE;2,OFFLINE)
local node group sgtype node_count
node=$1
group=$2
oLog des "Check service group status"
RExec root $node "/opt/VRTSvcs/bin/hagrp -state $group"
node_count=`echo "$out"|sed 1d|wc -l`
RExec root $node "cat $autotcmaincf"
echo "$out"|grep -A 10 -P "^\s*group\s*$group"|grep -iP "Parallel\s*=\s*1" > /dev/null 2>&1 && sgtype=1 || sgtype=0
RExec root $node "/opt/VRTSvcs/bin/hagrp -state $group"
out=`echo "$out"|grep ^$group|grep ONLINE|wc -l`
if [ "$out" = 0 ]
then
	return 2
elif [ "$out" = 1 -a "$sgtype" = 0 ]
then
	return 0
elif [ $out -lt $node_count -a "$sgtype" = 1 ]
then
	return 1
elif [ "$out" = $node_count ]
then
	return 0
fi
}

waitGroupOnline(){
#DES:Waiting group online(0,success;1,failed)
local sg node_count sgtype
node=$1
group=$2
oLog des "Waiting the group $group online"
RExec root $node "/opt/VRTSvcs/bin/hagrp -state $group"
node_count=`echo "$out"|sed 1d|wc -l`
RExec root $node "cat $autotcmaincf"
echo "$out"|grep -A 10 -P "^\s*group\s*$group"|grep -iP "Parallel\s*=\s*1" > /dev/null 2>&1 && sgtype=1 || sgtype=0
for i in `seq 60`
do
        sleep 10
        RExec root $node "/opt/VRTS/bin/hagrp -state $group"
	out=`echo "$out"|grep ONLINE|wc -l`
	if [ "$out" = 1 -a "$sgtype" = 0 ] || [ "$out" = "$node_count" ]
	then
		break
	fi
	
done
RExec root $node "/opt/VRTS/bin/hagrp -state $group"
out=`echo "$out"|grep ONLINE|wc -l`
if [ "$out" = 1 -a "$sgtype" = 0 ] || [ "$out" = "$node_count" ]
then
	return 0
else
        RExec root $node "/opt/VRTSvcs/bin/hagrp -clear $group"
        RExec root $node "/opt/VRTSvcs/bin/hagrp -online $group -any"
        for i in `seq 60`
        do
                sleep 10
                RExec root $node "/opt/VRTS/bin/hagrp -state $group"
                out=`echo "$out"|grep ONLINE|wc -l`
                if [ "$out" = 1 -a "$sgtype" = 0 ] || [ "$out" = "$node_count" ]
                then
                        break
                fi
        done
        RExec root $node "/opt/VRTS/bin/hagrp -state $group"
        out=`echo "$out"|grep ONLINE|wc -l`
        if [ "$out" = 1 -a "$sgtype" = 0 ] || [ "$out" = "$node_count" ]
        then
                return 0
        else
                oLog error "Group $group failed to be online"
                myexit 1
        fi
fi
}
waitNodeGroupOnline(){
#des:Waiting one node's group online
local sg node n
node=$1
sg=$2
n=0
oLog des "Waiting group $sg to be online on the node $node"
for i in `seq 60`
do
        sleep 5
        RExec root $node "/opt/VRTSvcs/bin/hagrp -state $sg -sys $node"
        echo "$out" |grep -i ONLINE > /dev/null 2>&1 && break
        n=$[$n+1]
done
[ $n -eq 60 ] && oLog error "Group $sg failed to be online on node $node" && myexit 1
}
waitNodeGroupOffline(){
#des:Waiting one node's group offline
local sg node n
node=$1
sg=$2
n=0
oLog des "Waiting group $sg to be offline on the node $node"
for i in `seq 60`
do
        sleep 5
        RExec root $node "/opt/VRTSvcs/bin/hagrp -state $sg -sys $node"
        echo "$out" |grep -i OFFLINE > /dev/null 2>&1 && break
        n=$[$n+1]
done
[ $n -eq 60 ] && oLog error "Group $sg failed to be offline on node $node" && myexit 1
}


waitGroupOffline(){
#DES:Waiting group offline(0,success;1,failed)
local sg node_count sgtype
node=$1
group=$2
oLog des "Waiting the group $group offline"
RExec root $node "/opt/VRTSvcs/bin/hagrp -state $group"
node_count=`echo "$out"|sed 1d|wc -l`
RExec root $node "cat $autotcmaincf"
echo "$out"|grep -A 10 -P "^\s*group\s*$group"|grep -iP "Parallel\s*=\s*1" > /dev/null 2>&1 && sgtype=1 || sgtype=0
for i in `seq 60`
do
        sleep 10
        RExec root $node "/opt/VRTS/bin/hagrp -state $group"
	out=`echo "$out"|grep ONLINE|wc -l`
	if [ "$out" = 0 ]
        then
                break
        fi
    
done
RExec root $node "/opt/VRTS/bin/hagrp -state $group"
out=`echo "$out"|grep ONLINE|wc -l`
if [ "$out" = 0 ]
then
        return 0
else
	oLog error "Group $group failed to be offline"
	myexit 1
fi
}

checkGroupStatusOnNode(){
#DES:check group status,retcode(0,ONLINE;1,OFFLINE)
local node group
node=$1
group=$2
RExec root $node "/opt/VRTSvcs/bin/hagrp -state $group -sys $node"
[ "$out" = ONLINE ] && return 0 || return 1
}

stopVCSAgentALL(){
#DES:Stop agent and service group on all nodes(0,Successful;1,failed)
local node seq file
file=$logs/nodefile
echo "$NODES"|xargs -n1 > $file
RExec root $NODE1 "/opt/VRTSvcs/bin/hastop -all"
seq=1
for i in `seq 60`
do
        sleep 10
        cat $file|grep -P "^[a-zA-Z]" > /dev/null 2>&1 || break
        for node in `cat $file|grep -P "^[a-zA-Z]"`
        do
                RExec root $node "NOERROR:/opt/VRTSvcs/bin/hasys -list"
                [ $? -eq 0 ] || sed -i -r "s/$node//" $file
        done
        seq=$[$i+1]
done
sleep 5
if [ $seq -eq 61 ] 
then
	oLog error "Failed to stop VCS agent"	
	myexit 1
fi
}

forceStopVCSAgentALL(){
#DES:Force stop agent and service group on all nodes(0,Successful;1,failed)
local node seq file
file=$logs/nodefile
echo "$NODES"|xargs -n1 > $file
RExec root $NODE1 "/opt/VRTSvcs/bin/hastop -all -force"
seq=1
for i in `seq 60`
do
        sleep 10
        cat $file|grep -P "^[a-zA-Z]" > /dev/null 2>&1 || break
        for node in `cat $file|grep -P "^[a-zA-Z]"`
        do
                RExec root $node "NOERROR:/opt/VRTSvcs/bin/hasys -list"
                [ $? -eq 0 ] || sed -i -r "s/$node//" $file
        done
        seq=$[$i+1]
done
sleep 5
if [ $seq -eq 61 ] 
then
	oLog error "Failed to stop VCS agent"	
	myexit 1
fi
}

startVCSAgent(){
#DES:Start agent and service group on all nodes(0,Successful;1,failed)
local node
node=$1
RExec root $node "/opt/VRTSvcs/bin/hastart"
for i in `seq 60`
do
        sleep 10
        RExec root $node "NOERROR:/opt/VRTSvcs/bin/hasys -state"
	echo "$out"|grep RUNNING > /dev/null 2>&1 && break
	echo "$out"|grep ADMIN_WAIT > /dev/null 2>&1 && RExec root $node "NOEXIT:/opt/VRTSvcs/bin/hasys -force $node"
done
RExec root $node "NOERROR:/opt/VRTSvcs/bin/hasys -state"
if [ $? -eq 0 ] 
then
	return 0
else
	oLog error "Failed to start VCS agent"
	myexit 1
fi
}

startVCSAgentALL(){
#DES:Start agent and service group on all nodes(0,Successful;1,failed)
local node
startVCSAgent $NODE1
for node in $OTHER
do
	RExec root $node "/opt/VRTSvcs/bin/hastart"
done
node_count=`echo "$NODES"|awk '{print NF}'`
for i in `seq 60`
do
	sleep 10
        RExec root $NODE1 "NOERROR:/opt/VRTSvcs/bin/hasys -state"
	out=`echo "$out"|grep RUNNING|wc -l`
        [ "$out" = "$node_count" ] && break
done
RExec root $NODE1 "/opt/VRTSvcs/bin/hasys -state"
out=`echo "$out"|grep RUNNING|wc -l`
if [ "$out" = "$node_count" ]
then
	return 0
else
	oLog error "Failed to start VCS agent"
	myexit 1
fi
}
waitVCSAgentOnline(){
#DES:Wait for vcs agent online on all nodes(0,online;1,offline)
local node anode
node=$1
oLog des "Check and wait vcs agent online on all nodes"
for i in `seq 60`
do
	sleep 10
	RExec root $node "NOERROR:/opt/VRTSvcs/bin/hasys -state"
	anode=`echo "$out"|grep RUNNING|wc -l`
	[ $anode -eq $NODESN ] && break
done
if [ $anode -lt $NODESN ]
then
	oLog error "VCS Agent Failed to be online"
	myexit 1
fi
}

waitVCSAgentOnlineOnNode(){
#DES:Wait for vcs agent online on all nodes(0,online;1,offline)
local node
node=$1
oLog des "Check and wait vcs agent on node $node"
for i in `seq 60`
do
        sleep 10
        RExec root $node "NOERROR:/opt/VRTSvcs/bin/hasys -state $node"
        [ "$out" = RUNNING ] && break
done
if [ "$out" != RUNNING ]
then
        oLog error "VCS Agent Failed to be online"
        myexit 1
fi
}

importMainCf(){
#DES:Import main.cf
local file a flag
file=$1
flag=0
oLog des "import the maincf $file to cluster"
if ! a=`stopVCSAgentALL`
then
        a=`forceStopVCSAgentALL`
        flag=1
fi
if [ -f $file ]
then
	:
else
	oLog error "$file doesn't exist!"
	myexit 1
fi

copyFileToRemote $file $NODE1
RExec root $NODE1 "mv /etc/VRTSvcs/conf/config/main.cf /etc/VRTSvcs/conf/config/main.cf.orig;cat /tmp/tmpfile.$PID > /etc/VRTSvcs/conf/config/main.cf"
a=`startVCSAgentALL` || return 1
if [ $flag -eq 1 ]
then
        for node in $NODES
        do
                {
                        waitNodeReboot $node
                } &
        done
fi
wait
}

checkCVMStatus(){
#DES:check if CVM are are online
oLog des "checking if cvm is configured and online"
noden=`echo $NODES|awk '{print NF}'`
RExec root $NODE1 "NOERROR:/opt/VRTS/bin/hagrp -state"
if [ `echo "$out"|grep ^cvm|grep ONLINE|wc -l` -eq $noden ]
then
        oLog des "CVM of all nodes \"$NODES\"are all online"
        return 0
else
        oLog des "CVM of all nodes \"$NODES\"are not all online"
        return 1
fi
}
lltLinkConfig(){
#DES:disconnect or connect all the llt link,opt should be disable or enable.
local node opt lltlinks lltlink nodecount num
node=$1
opt=$2
for i in `seq 30`
do
        RExec root $node "NOERROR:lltconfig"
        echo "$out"|grep -i "LLT is running" >/dev/null 2>&1 && break
        sleep 10
done
RExec root $node "cat /etc/llttab"
lltlinks=`echo "$out"|grep ^link|awk '{print $2}'|xargs -n10`
for lltlink in $lltlinks
do
         RExec root $node "lltconfig -t $lltlink -L $opt"
done
if [ $opt == "enable" ]
then
        nodecount=`echo "$NODES"|awk '{print NF}'`
        for i in `seq 60`
        do
                sleep 5
                RExec root $node "NOERROR:/opt/VRTS/bin/hasys -state"
                num=`echo "$out"|sed 1d|grep -i RUNNING|wc -l`
                [ $num -eq $nodecount ] && break
        done
fi
}
roundSwitchGroup(){
#DES:switch service group among nodes.
local node group current_node
group=$1
RExec root $NODE1 "/opt/VRTS/bin/hagrp -state"
current_node=`echo "$out"|grep -P "^$group.*ONLINE"|awk '{print $3}'`
for node in `echo "$NODES"|sed "s/$current_node//g"`
do
        switchGroup $node $group
done
switchGroup $current_node $group
}
checkFencingStatus(){
#DES:check if fencing is configured
local noden node_count
RExec root $NODE1 "vxfenadm -d"
echo "$out"|grep "Fencing Mode:"|grep -i disable > /dev/null 2>&1 && return 1
noden=`echo "$out"|grep -A 100 -P "State Information"|grep running|wc -l`
[ $noden -ne $NODESN ] && return 1
return 0
}
getMasterNode(){
#DES:getting master node
local master
RExec root $NODE1 "vxdctl -c mode"
master=`echo "$out"|grep ^master:|awk '{print $2}'`
if [ -z "$master" ]
then
	oLog error "Failed to get master node name"
	myexit 1
else
	echo $master
fi
}
