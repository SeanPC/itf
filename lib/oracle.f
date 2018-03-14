startOracle(){
#DES:start oracle,nodes need separated by space
local nodes node
nodes=$1
if [ -z "$oracletype" ]
then
	oLog error "Please define oracletype before using function startOracle"
	myexit 201
fi
oLog des "Starting Oracle"
if [ "$oracletype" = RAC ]
then
	for node in $nodes
	do
		OExec $node 'startup;' 'opened' 'ERROR'
	done
else
	node=`echo "$nodes"|awk '{print $1}'`
	OExec $node 'startup;' 'opened' 'ERROR'
fi	
}

stopOracle(){
#DES:stop oracle,nodes need separated by space
local nodes node
nodes=$1
if [ -z "$oracletype" ]
then
        oLog error "Please define oracletype before using function stopOracle"
        myexit 201
fi
oLog des "Stopping Oracle"
if [ "$oracletype" = RAC ]
then
        for node in $nodes
        do
                OExec $node 'shutdown immediate;' 'dismounted' 'ERROR'
        done
else
        node=`echo "$nodes"|awk '{print $1}'`
	OExec $node 'shutdown immediate;' 'dismounted' 'ERROR'
fi
}

checkOdmLink(){
#DES:check if seetingup odm link
local node ret
oLog des "Checking if relink oracle odm libray to Veritas odm libray"
for node in $NODES
do
	ret=`RExec root $node 'ls -l /oracle/orahome/lib/libodm*|grep ^l' 'VRTSodm'` || exit 201
done
}
checkInstOpen(){
#DES:check if instance is open
local node=$1
oLog des "Checking if Oracle instance is OPEN"
out=`OExec $node 'select instance_name,status from v$instance;' 'OPEN' 'mount|start' && echo "$out"` || exit 201
}
checkArchEnable(){
#DES:check if archive mode is enabled
local node=$1
oLog des "Checking if Archive log mode is enabled"
out=`OExec $node 'archive log list;' 'Enabled' && echo "$out"` || exit 201
}
getDatafile(){
#DES:Getting datafile name and path.
oLog des "Getting datafile path and name"
OExec $NODE1 'select name from v$datafile;'
}
checkOracleByInst(){
#DES:Check Oracle status by specified instance
local inst ext
inst=$1
ext=$2
export oraclesid=$inst
OExec $NODE1 'select instance_name,status from v$instance;' 'OPEN'
OExec $NODE1 'select name from v$datafile;'
[ "$ext" = tmp ] && OExec $NODE1 'select name from v$tempfile;'
}

oracleStressStart(){
#DES:Add IO stress for oracle database
oLog des "Add IO for oracle database"
local file node pid0
node=$1
dg=$2
file=$BASE/etc/io_oracle.sh
copyFileToRemote $file $node
RExec $oracle $node "ps -ef"
pid0=`echo "$out"|grep -v grep|grep tmpfile|awk '{print $3}'|sort -n|uniq -c|sort -n|awk '{print $2}'|xargs -n100`
[ -n "$pid0" ] && RExec $oracle $node "NOERROR:kill -9 $pid0"
sleep 5
RExec root $node "vxstat -g $dg -i 2 -c 5 -u h"
RExec $oracle $node "nohup /tmp/tmpfile.$PID 1 1 > /tmp/.oracle.stress 2>&1 &"
RExec $oracle $node 'cat /tmp/.oracle.stress'
oraclepid=`echo "$out"|grep -oP "\d+"|xargs -n 1000`
sleep 10
RExec root $node "vxstat -g $dg -i 2 -c 10 -u h"
}
oracleStressStop(){
#DES:Stop IO stress for oracle database
local node
oLog des "Stop IO for oracle database"
node=$1
if [ -z "$oraclepid" ]
then
        oLog error "There is no oracle stress process"
        myexit 1
fi
RExec $oracle $node "kill -9 $oraclepid"
}
