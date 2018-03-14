#!/bin/bash
#shared and service lib


Usage(){
cat << EOF

Usage:
        tcstart -node NODE1,[NODE2...] -tc TC1,[TC2...] [-clear no] [ -isvcs no ] [-tctimeout SECONDS]

EOF
}

myexit(){
#DES:exit process with required operations.
local ret
ret=$1
[ "$ret" = 250 ] && oLog error "Process canceled by User."
oLog des "Test case exit with code $ret"
GetTcResult
[ "$ret" = 250 ] && statisTCResult && unLockNode
if [ $ret = 0 ]
then
	exit 0
elif [ $ret = 1 ]
then
	#will push clearenv
	exit 1
elif [ $ret = 10 ]
then
	#will push clearenv
	exit 10
else
	exit $ret
fi
}

GetArg(){
local opts opt i
opts=`echo "$ARGS"|sed -r "s/ -node | -tc | -clear | -isvcs | -tctimeout /\n&/g"|sed -r "s/^\s+//"`
i=0
for opt in node tc clear isvcs tctimeout
do
        arg[$i]=`echo "$opts"|grep "^-$opt "|awk '{print $2}'`
        if [ "$i" -lt 2 ] && [[ "${arg[$i]}" =~ ^$|^-|,$ ]] 
        then
                Usage
                exit 1
        fi
        i=$[$i+1]
done
}

#Operation log
oLog(){
#DES:print log to olog file
local type des date stime ltime etime
type=$1
des=$2
date=`date "+%Y-%m-%d %H:%M:%S"`
case "$type" in 
        head)
                echo -e "\n==================== Operation Log for TC $tc ===================="
		echo "DATE:$date"
		echo "Nodes:$NODES"
                ;;
        step)
                echo -e "\n\n====STEP: $des"
                echo "DATE:$date"
                ;;
	des)
		echo -e "\n***$des***\n"
		;;
	error)
		echo -e "\n\nTCERROR: $des\n"
		;;
        exec)
		mixcode='[\[0-9;m]*||\[m|\[[A-Z]{1}|||\(B'
		out=`echo "$out"|sed -r "s/$mixcode//g;s/Downloading/\nDownloading/g"`
		if [ "$result" = Passed ]
		then
                	echo -e "\n\nDATE:$date\nHOST:$host\nUSER:$user\nSTDIN:$cmd\nSTDOUT:"
			echo "$out"
		else
                        [ $ret = 137 ] && result+="[killed by system as timetout]"
			echo -e "\n\nDATE:$date\nHOST:$host\nUSER:$user\nSTDIN:$cmd\nSTDOUT:"
			echo "$out"
			echo -e "RETURN:$ret\nRESULT:$result"
		fi
                ;;
        space)
                echo -e "\n\n"
                ;;
	case)
		stime=`cat $olog|head -5|grep -oP "(?<=DATE:).*"|head -1`
		[ -z "$stime" ] && stime=$date
		stime=`date -u +%s -d "$stime"`
		etime=`date -u +%s -d "$date"`
		ltime=$[$etime-$stime]
		ltime="`echo $ltime/60|bc`m`echo $ltime%60|bc`s"
                echo -e "\n\nCase Result:$des"
                echo "DATE:$date"
		echo "Duration:$ltime"
		;;
	flag)
		echo -e "\n\n\nFlag line to indicate case is completed.\n\n\n"
		;;
        *)
                return 1
esac >> $olog
}

getEnvfile(){
#get user's profile
local out path
if [ -z "$envfile" -a "$user" != root ]
then
        out=`$SSH $user@$host "pwd;ls -a"`
        path=`echo "$out"|head -1`
        echo "$out"|grep \.bash_profile > /dev/null && export envfile=$path/.bash_profile || export envfile=$path/.profile
fi
}

includeExcludeHint(){
[ "$result" != noexit:Failed ] && [ "$result" != Failed ] && return 0
if [ -n "$in" ] 
then
        [ $include -ne 0 ] && oLog error "The output need include $in,but it doesn't include $in" || oLog des "The output already include $in"
fi
if [ -n "$ex" ]
then
        [ $exclude -ne 0 ] && oLog error "The output couldn't include $ex,but it contains $ex" || oLog des "The output doesn't include $ex" 
fi
}
LExec(){
#DES:excute local cmds(LExec CMD [Include] [Exclude])
local i include exclude in ex
cmd=$1
include=$2
exclude=$3
user=root
host=`hostname`
in="$include"
ex="$exclude"
exit=yes
#NOEXIT: known issue,prompt waring
#noexit: it is error,but not exit as there will be extral operation
#NOERROR: it is not error,it fails with expect.
if echo "$cmd"|grep NOEXIT: > /dev/null 2>&1
then
        cmd=`echo "$cmd"|sed "s/NOEXIT://"`
        exit=no1
elif echo "$cmd"|grep noexit: > /dev/null 2>&1
then
        cmd=`echo "$cmd"|sed "s/noexit://"`
        exit=no2
elif echo "$cmd"|grep NOERROR: > /dev/null 2>&1
then
        cmd=`echo "$cmd"|sed "s/NOERROR://"`
        exit=no3
fi
echo "$cmd" > /tmp/exec.$PID
out=`sh /tmp/exec.$PID 2>&1 && rm -f /tmp/exec.$PID`
ret=$?
if [ -z "$include" ]
then
        include=0
else
        for i in `echo "$include"|sed "s/,/ /g"`
        do
                if echo "$out"|grep -P "$i" > /dev/null 2>&1
                then
                        include=0
                else
                        include=1
                        break
                fi
        done
fi
if [ -z "$exclude" ]
then
        exclude=0
else
        echo "$out"|grep -P "$exclude" > /dev/null 2>&1 && exclude=1 || exclude=0
fi
if [ $ret -eq 0 -a $include -eq 0 -a $exclude -eq 0 ]
then
	result=Passed
	oLog exec
else
        if [ "$exit" = no1 ]
        then
                result=WARNING
        elif [ "$exit" = no2 ]
        then
                result=Failed
        elif [ "$exit" = no3 ]
        then
                result=Passed
        else
                result=Failed
        fi
        oLog exec
	includeExcludeHint
        [ "$exit" = yes ] && myexit 1 || return 1
fi
}

OExec(){
#DES:excute oracle sql sentences on remote node(OExec HOST CMD)
local include exclude in ex
user=$oracle 
host=$1
cmd=$2
include=$3
exclude=$4
in="$include"
ex="$exclude"
#getEnvfile
#out=`echo -e "$cmd\nexit;" | timeout $tctimeout $SSH $user@$host "cat > tmp.sql && . $envfile && sqlplus / as sysdba @tmp.sql && rm -f tmp.sql" 2>&1`
if [ -z $oraclesid ]
then
        out=`echo -e "$cmd\nexit;" | timeout $tctimeout $SSH root@$host "cat > /tmp/tmp.sql && su - $user -c 'sqlplus / as sysdba @/tmp/tmp.sql' && rm -f /tmp/tmp.sql" 2>&1`
else
        out=`echo -e "$cmd\nexit;" | $SSH root@$host "cat > /tmp/tmp.sql && su - $user -c 'ORACLE_SID=$oraclesid && export ORACLE_SID && sqlplus / as sysdba @/tmp/tmp.sql' && rm -f /tmp/tmp.sql" 2>&1`
fi
ret=$?
if [ -z "$include" ]
then
        include=0
else
        for i in `echo "$include"|sed "s/,/ /g"`
        do
                if echo "$out"|grep -P "$i" > /dev/null 2>&1
                then
                        include=0
                else
                        include=1
                        break
                fi
        done
fi
if [ -z "$exclude" ]
then
        exclude=0
else
        echo "$out"|grep -P "$exclude" > /dev/null 2>&1 && exclude=1 || exclude=0
fi
if [ $ret -eq 0 -a $include -eq 0 -a $exclude -eq 0 ]
then
        result=Passed
        oLog exec
else
        result=Failed
        oLog exec
	includeExcludeHint
        myexit 1
fi
}

RExec(){
#DES:excute cmds on remote node(RExec USER HOST CMD)
local include exclude ret path exit i in ex
user=$1
host=$2
cmd=$3
include=$4
exclude=$5
exit=yes
#getEnvfile
in="$include"
ex="$exclude"
if echo "$cmd"|grep NOEXIT: > /dev/null 2>&1
then
	cmd=`echo "$cmd"|sed "s/NOEXIT://"`
	exit=no1
elif echo "$cmd"|grep noexit: > /dev/null 2>&1
then
	cmd=`echo "$cmd"|sed "s/noexit://"`
	exit=no2
elif echo "$cmd"|grep NOERROR: > /dev/null 2>&1
then
        cmd=`echo "$cmd"|sed "s/NOERROR://"`
        exit=no3
fi
if [ "$user" = root ]
then
	out=`echo "$cmd"|timeout $tctimeout $SSH $user@$host "cat > /tmp/exec && sh /tmp/exec && rm -f /tmp/exec" 2>&1`
else
	#out=`echo "$cmd"|timeout $tctimeout $SSH $user@$host "cat > /tmp/exec1 && . $envfile && sh /tmp/exec1 2>&1 && rm -f /tmp/exec1"`
        out=`echo "$cmd"|timeout $tctimeout $SSH root@$host "cat > /tmp/exec && su - $user -c 'sh /tmp/exec' && rm -f /tmp/exec" 2>&1`
fi
ret=$?
if [ -z "$include" ]
then
	include=0
else
	for i in `echo "$include"|sed "s/,/ /g"`
	do
		if echo "$out"|grep -P "$i" > /dev/null 2>&1 
		then
			include=0 
		else
			include=1
			break
		fi
	done
fi
if [ -z "$exclude" ]
then
	exclude=0
else
	echo "$out"|grep -iP "$exclude" > /dev/null 2>&1 && exclude=1 || exclude=0
fi
if [ $ret -eq 0 -a $include -eq 0 -a $exclude -eq 0 ]
then
	result=Passed
	oLog exec
else
	if [ "$exit" = no1 ]
	then
		result=WARNING
	elif [ "$exit" = no2 ]
	then
		result=Failed
	elif [ "$exit" = no3 ]
	then
		result=Passed
	else
		result=Failed
	fi
	oLog exec
	includeExcludeHint
	if [ "$exit" = yes ]
        then
                if [ "$ret" = 255 ]
                then
                       LExec "ping -c 3 $host"
                       oLog des "will help to rerun comman,but need you manually check this step."
                       [ "$user" = root ] && out=`echo "$cmd"|$SSH $user@$host "cat > /tmp/exec && sh /tmp/exec 2>&1 && rm -f /tmp/exec"` || out=`echo "$cmd"|$SSH root@$host "cat > /tmp/exec && su - $user -c 'sh /tmp/exec 2>&1' && rm -f /tmp/exec"`
                       ret=$?
                       result=WARNING
                       oLog exec
                       [ $ret -eq 0 ] && return 1 || myexit 1
                else
                        myexit 1
                fi
        else
                return 1
        fi
fi
}

dataCompare(){
#DES:compare data.
local res target 
res=$1
target=$2

}

lockNode(){
#lock the nodes in the process
local node date proc
date=`date "+%Y-%m-%d %H:%M:%S"`
proc=`ps -ef`
for node in $NODES 
do
        if [ -f $BASE/lock/$node ] && echo "$proc"|grep tcstart|grep $node > /dev/null 2>&1
        then
                echo "$date: Node $node is locked by another case!" > $log
                exit 1
        else
                echo "$NODE1" > $BASE/lock/$node
        fi
done
}

unLockNode(){
#unlocak nodes when process finished
local node
cd $baselog
rm -f .pid .tcrun
for node in $NODES
do
        rm -rf $BASE/lock/$node
done
}

GetTcResult(){
#get case result
local file result step step0
if cat $olog|grep -P "^RESULT:Failed$|^TCERROR:" > /dev/null 2>&1 || ! cat $olog|grep "Flag line to indicate" > /dev/null 2>&1
#if cat $olog|grep -P "^RESULT:Failed$|^TCERROR:" > /dev/null 2>&1
then
	result=Failed
else
	cat $olog|grep "RESULT:WARNING" > /dev/null 2>&1 && result="Passed with Waring" || result=Passed
fi
oLog case $result
}

statisTCResult(){
grep -l "^Case Result:Failed" $baselog/*.olog|grep -oP "\w+(?=\.olog)" > $baselog/failed_tc
}

importValue(){
local define tmpdef
define=$baselog/define
tmpdef=$BASE/tmp/tmpdef.$PID
if [ -f $define ] && [ `cat $define|wc -l` -gt 0 ]
then
	echo "define(){" > $tmpdef
	cat $define >> $tmpdef
	echo "}" >> $tmpdef
	source $define
	if [ $? -ne 0 ]
	then
		oLog error "syntax error in the user defined file"
		rm -f $tmpdef
		exit 1
	fi	
	rm -f $tmpdef
fi
}
checkRequire(){
local tcs char chars tc tmpcheck
local tcs=$1
tmpcheck=$BASE/tmp/tmpcheck.$PID
#all var should devided by ","
#check required vaule
for tc in $tcs
do
	cat $basetc/$tc.tc|grep VALUE|cut -d : -f 2|sed "s/,/ /g"
done|xargs -n1|sort -n|sort -u > $BASE/tmp/chars.$PID
chars=`cat $BASE/tmp/chars.$PID|xargs -n 10000` && rm -f $BASE/tmp/chars.$PID
for char in $chars
do
	echo "[ -n \"\$$char\" ]" > $tmpcheck
	sh $tmpcheck
	if [ $? -ne 0 ]
	then
		oLog error "$char of the required variables($chars) is not defined!"
		rm -f $tmpcheck
		exit 1
	fi
done
rm -f $tmpcheck
}

orderTC(){
#to order the tcs
local tc0 prio
for tc0 in $tcs
do
	prio=`cat $basetc/$tc0.tc|grep "#P"` && echo "$tc0:$prio"  || echo "$tc0:#P:55"
done|sed "s/ //g"|sort -k 3 -t :|cut -d : -f 1|xargs -n1000
}

checkTC(){
local tc valid_tcs
valid_tcs=`echo ${arg[1]}|sed "s/,/ /g"`
importValue
[ "$isvcs" = no ] || tcs=print_env
for tc in $valid_tcs
do
	[[ "$tc" =~ \.tc$ ]] && tc=`echo $tc|cut -d . -f 1`
	if [ -f $basetc/$tc.tc ] && [ `cat $basetc/$tc.tc|wc -l` -gt 0 ]
	then
		tcs+=" $tc"
	else
        	echo "Invalid case \"$tc\"" >>  $log
        	exit 1
	fi
done
checkRequire "$tcs"
tcs=`orderTC`
echo "$tcs"|awk '{print $1}' > $baselog/.printenv
}
clearENV(){
local maincf0 maincf1 node mp0 mp1 mp a
source $logs/define > /dev/null 2>&1 
olog=$logs/$tc.clearenv
> $olog
local node ret
a=`clearMisc`
#ret=`checkNode root` || return 1
if [ "$isvcs" != no ]
then
	maincf0=`cat $MAINCF`
	RExec root $NODE1 "cat $autotcmaincf"
	maincf1="$out"
	mp0=`echo "$maincf0"|grep MountPoint|grep -oP "(?<=\")/\w+"|xargs -n1000|sed "s/ /,/g"`
	if [ "$maincf0" != "$maincf1" ]
	then
		importMainCf $MAINCF || return 1
		if echo "$maincf0" |grep cvm > /dev/null 2>&1
		then
			a=`waitGroupOnline $NODE1 cvm` || return 1
		fi
	fi
fi
#umount manual mount fs
for node in $NODES
do
	umountVxfs $node $mp0
done
#destroy sfcache dg
a=`clearSfcache`
#destroy dg and unexport disks and...
for node in $NODES
do
	a=`cleanALLDg $node`
	a=`unexportDisks $node`
	a=`includeDisks $node`
	a=`formatToCdsdisk $node`
done
clearTmpFile
}
defineGlobalValue(){
#DES:define global vaule
autotcengineA="/var/VRTSvcs/log/engine_A.log"
autotcmaincf="/etc/VRTSvcs/conf/config/main.cf"
}
