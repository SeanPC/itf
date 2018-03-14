checkSshAuthorize(){
#DES:check if could ssh login host without password
local user target
user=$1
target=$2
expect << EOF >/dev/null 2>&1
#expect -d << EOF
set timeout $TIMEOUT
spawn ssh -l $user $target
expect {
   "*#" {
      exit 0
   }
   "*>" {
      exit 0
   }
   "*word: " {
      exit 1
   }
  "$user*" {
      exit 0
   }
   eof {
      exit 2
   }
   timeout {
      exit 3
   }
}
expect eof
EOF
return $?
}

checkNode(){
#DES:check node are pingable and wop-sshable and check if the nodes are belong to a cluster when opt not equal to novcs
local host user cmd out result nodes node nodesn opt type
user=$1
opt=$2
oLog des "Getting driver node name and ip"
LExec 'hostname;ifconfig'

oLog des "checking if hosts are wop-sshable with $user"
if which nmap > /dev/null 2>&1
then
	:
else
	oLog error "Missing command nmap"
	myexit 1
fi
for host in $NODES
do
	out=`nmap -p 22 $host 2>&1`
        if ! echo "$out"|grep -P "open\s+ssh" > /dev/null 2>&1
        then
		cmd="nmap -p 22 $host"
		result=Failed
		oLog exec 
		myexit 249
        elif ! checkSshAuthorize $user $host
        then
                cmd="ssh -l $user $host"
		out="Password: "
		result=Failed
		oLog exec
		myexit 249
        else
		cmd="ssh -l $user $host"
		out=""
		result=Passed
		oLog exec 
        fi
	$SSH root@$host "rm -rf /tmp/exec*" > /dev/null 2>&1
done
type=`ssh $NODE1 "uname" 2>&1|tail -1|cut -c 1`
[ "$user" = root -a "$type" = L ] && LExec "$BASE/etc/setssh ${arg[0]}"
i=0
if [ "$user" = root -a "$isvcs" != no -a "$opt" != novcs ]
then
	for node in $NODES
	do
		out=`RExec root $node "/opt/VRTS/bin/hasys -list" && echo "$out"` || exit 249
		nodes[$i]=`echo "$out"|xargs -n 100`
		i=$[$i+1]
	done
	nodesn=$[${#nodes[*]}-1]
	for i in `seq $nodesn`
	do
		if [ "${nodes[0]}" != "${nodes[$i]}" ]
		then
			oLog error "The Nodes specified are not in a cluster"
			myexit 249
		fi
	done
	if [ "`echo "$NODES"|xargs -n1|sort -n`" != "`echo "${nodes[0]}"|xargs -n1|sort -n`" ]
	then
		oLog error "Please fill in all nodes in the cluster"
		myexit 249
	fi
fi
}

copyFileToRemote(){
#DES:Copy File to remote
local file node
file=$1
node=`echo $2|sed "s/ //g"`
user=root
LExec "$SCP $file $node:/tmp/tmpfile.$PID"
}
copyFileToRemoteKeepName(){
#DES:Copy File to remote,will keep the name,this is a enhanced way for copyFileToRemote.
local file node file1
file=$1
node=`echo $2|sed "s/ //g"`
user=root
file1=`basename $file`
LExec "$SCP $file $node:/$file1.$PID"
RExec root $node "ls /" "$file1.$PID"
}

waitNodeReboot(){
#DES:Let node finish reboot process.will do reboot node and wait for it offline,then online.
local node
node=$1
rebootNode $node
waitNodeOffline $node
waitNodeOnline $node
}

rebootNode(){
#DES: initialize reboot operation on the node
local node
node=$1
oLog des "Rebooting node \"$node\"!"
if [ -z "$type" ]
then
	oLog error "You must define type first in function rebootNode"
	myexit 1
fi
if [ $type = L ]
then
	RExec root $node "nohup reboot -nf > /dev/null 2>&1 &"
else
	RExec root $node "nohup reboot -n > /dev/null 2>&1 &"
fi
}

localLog(){
user=root
host=`hostname`
result="Passed"
cmd=$1
oLog exec
}
waitNodeOffline(){
#DES:Waiting node to be offline
local node i status
node=$1
oLog des "Waiting node \"$node\" offline"
for i in `seq 2000`
do
	sleep 1
	out=`nmap -p 22 $node 2>&1`
	if echo "$out"|grep open > /dev/null 2>&1
	then
		localLog "nmap -p 22 $node 2>&1"
		continue
	else
		out=`nmap -p 22 $node 2>&1`
		if echo "$out"|grep open > /dev/null 2>&1
		then
			localLog "nmap -p 22 $node 2>&1"
			continue
		else
			
			localLog "nmap -p 22 $node 2>&1"
			oLog des "Node \"$node\" is offline"
			return 0
		fi
	fi
done
oLog error "Timeout to offline node \"$node\" "
myexit 1
}

waitNodeOnline(){
#DES:Waiting node to be online
local i node status ret
node=$1
oLog des "Waiting node \"$node\" online"
for i in `seq 60`
do
        sleep 60
	out=`$SSH root@$node "hostname" 2>&1`
	ret=$? && localLog "ssh root@$node \"hostname\""
	if [ $ret = 0 ]
        then
		sleep 10
		oLog des "Node \"$node\" is online"
		return 0
        else
		continue
        fi
done
oLog error "Timeout to online node \"$node\" "
myexit 1
}

clearTmpFile(){
#DES:clear tmp file 
local file
cd $BASE/tmp/
for file in `ls|grep ^$tc`
do
	rm -rf $file
done
cd
}
replaceString(){
#DES:replaceString key1,key2,key3.. value1,,value2,,value3.. filename
oLog des "Replacing strings usging replaceString"
local keys values file i exp
keys=$1
values=$2
file=$3
[ -f $file ] || return 1
keys=(`echo "$keys"|sed "s/,/ /g"`)
values=(`echo "$values"|sed "s/,,/ /g"`)
[ "${#keys[*]}" -ne "${#values[*]}" ] && return 1
for ((i=0;i<${#keys[*]};i++))
do
        exp+="s/${keys[$i]}/${values[$i]}/g;"
done
sed -i "$exp" $file
[ $? -eq 0 ] && return 0 || return 1
}
setNodeDate(){
#DES:set system date by ntp server
local node
for node in $NODES
do
        RExec root $node "NOERROR:ntpdate 172.16.8.14"
done
}
setNodeEquivalence(){
#DES:configure user equivalence from node1 to all other
#set ssh wop and ntpdate
local node pubkeydir pubkey
case $type in
        L)
                pubkeydir=/root/.ssh
                ;;
        A)
                pubkeydir=/.ssh
                ;;
        S)
                 [[ $autotcos =~ solaris11 ]] && pubkeydir=/root/.ssh || pubkeydir=/.ssh
esac
RExec root $NODE1 "[ -f $pubkeydir/id_rsa.pub ] || echo y|ssh-keygen -t rsa -N '' -f $pubkeydir/id_rsa"
RExec root $NODE1 "cat $pubkeydir/id_rsa.pub"
pubkey="$out"
for node in $OTHER
do
        RExec root $node "mkdir -p $pubkeydir"
        echo "$pubkey"|$SSH $node "cat $pubkeydir/authorized_keys|grep \"$pubkey\" > /dev/null 2>&1 || cat >> $pubkeydir/authorized_keys"
done
}
turnNodesToIp(){
#DES:trun hostname to ip(nodes could be empty or specified by space)
local node ip nodes ips
nodes=$1
[ -z "$nodes" ] && nodes="$NODES"
for node in $nodes
do
        ip=`host $node|grep -oP "(?<=address )[\d\.]+"`
        [ -z "$ip" ] && ip=`cat /etc/hosts|awk '$2 ~ /'$node'/{print $1}'`
        if [ -z "$ip" ]
        then
                oLog error "Failed to trun $node to ip address"
                myexit 201
        else
                ips+=" $ip"
        fi
done
echo "$ips"|sed -r "s/^\s+//"
}
getNodeStatusAfterPanic(){
#DES:judge if panic succesful and display the active node and panic node
local node file activenode panicnode i subpid nsubpid nodes sd
file=$BASE/tmp/panicflag.$PID
subpid=$BASE/tmp/subpid.$PID
rm -f $file $subpid
for node in $NODES
do
	{
		echo $! >> $subpid 
		for i in `seq 1000`
		do
			ping -c 3 $node > /dev/null 2>&1
			[ $? -ne 0 ] && touch $file
		done
	} &
done
for i in `seq 600`
do
	sleep 1
	if [ -f $file ]
	then
		sd=`cat $subpid|xargs -n 100`
		kill -9 $sd > /dev/null 2>&1
		nodes=`echo $NODES|sed -r 's/ /|/g'`
                nsubpid=`cat $subpid|sed -e '/^$/d'|wc -l`
                [ $nsubpid -ne 2 ] && kill -9 `ps -ef|grep "ping -c"|grep -v grep|grep -E "$nodes"|awk '{print $3}'|xargs -n10` >/dev/null 2>&1
		break
	fi
done
if [ ! -f $file ]
then
	oLog error "Time out to wait one node panic"
	myexit 1
fi
for node in $NODES
do
	LExec "NOERROR:ping -c 3 $node"
	[ $? -eq 0 ] && activenode+=" $node" || panicnode+=" $node"
done
echo "Active:$activenode"
echo "Panic:$panicnode"
rm -f $file $subpid
}
getRandomFromList(){
#DES:get random member of a list which seperated by ,
local str len i
str=$1
len=`echo "$str"|awk -F "," '{print NF}'`
i=`echo "$RANDOM%$len+1"|bc`
echo "$str"|awk -F "," '{print $'"$i"'}'
}
