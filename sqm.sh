#!/bin/bash

umask 0022
LANT=C; export LANG

PATH='/usr/bin:/bin'
IFS=$(printf ' \t\n_'); IFS=${IFS%_}


unset OPTT OPTS OPTI OPTU OPTP OPTN OPTL
while getopts hlt:i:s:u:p:n: OPT; do
	case $OPT in
	t) OPTT="$OPTARG" ;;
	i) OPTI="$OPTARG" ;;
	s) OPTS="$OPTARG" ;;
	u) OPTU="$OPTARG" ;;
	p) OPTP="$OPTARG" ;;
	n) OPTN="$OPTARG" ;;
	l) OPTL=1 ;;
	h) usage 0 ;;
	\?) usage 1 ;;
	esac
done
shift `expr "$OPTIND" - 1`

export ORACLE_SID=${OPTS-"orcl"} || exit 1
export ORACLE_HOME=$(grep "$ORACLE_SID" /etc/oratab | sed -e 's/^\w*://' -e 's/:N$//')
export PATH="$PATH":"$ORACLE_HOME"/bin

USER=${OPTU-"oracle"} # set oracle user
PASS=${OPTP-"passwd"} # set oracle password

# SQLPlus 
if test x${OPTN-set} = xset; then
	SQLPLUS="sqlplus -s $USER/$PASS"
else
	NET="$OPTN"; SQLPLUS="sqlplus -s $USER/$PASS@$NET"
fi

# Interval Default 10 Seconds 
SLP=${OPTI-10}

# Table name
TBL=${OPTT-"TEST_TABLE"}


usage()
{
  exec >&2
  echo "usage: `basename \"$0\"` [ -t TABLE_NAME ] [ -s SID ] [ -i Interval ] [ -u DB USER ] [ -p DB PASSWORD ] [ -n NET IDENTIFIED ] [ -l ]"
  echo '    -t table name default TEST_TABLE'
  echo '    -s ORACLE_SID Default orcl'
  echo '    -i Interval Time for Query Transaction'
  echo '    -u Oracle Database User Default oracle' 
  echo '    -p Oracle Database User Password Default passwd'
  echo '    -n Network Identified in tnsname.ora'
  echo '    -l enbale logging mode'
  echo '    -h Print option help.'
  exit "${1-127}"
}


echo()
{
  printf '%s\n' "$*"
}


logging()
{
	# loggin ON/OFF
	if test x${OPTL+set} = xset; then
		local time=$(date "+%Y/%m/%d %H:%M:%S")
		local func=${1:-"Exec Function Name"}
		local message=${2:-"Exec SQL"}
		local dir=${3:-/tmp/$(date "+%Y%m%d")}
		local file=${4:-$(echo $$).log}

		test -d "$dir" || mkdir "$dir" || exit 1
		printf "%-22s | %-15s | %-30s\n" "$time" "$func" "$message" >> "$dir"/"$file"
	else
		return
	fi
}


# ---------------------------------------------------
# FUNCTION CREATE TABLE
# ---------------------------------------------------
CREATE_TABLE()
{
	( echo "CREATE TABLE $TBL(A NUMBER PRIMARY KEY, B VARCHAR(100), C TIMESTAMP DEFAULT SYSTIMESTAMP);"
	  echo 'exit') | $SQLPLUS >/dev/null 2>&1
}


# ---------------------------------------------------
# FUNCTION DROP TABLE
# ---------------------------------------------------
DROP_TABLE()
{
	( echo "DROP TABLE $TBL;" ) | $SQLPLUS >/dev/null 2>&1
}


# ---------------------------------------------------
# FUNCTION SELECT COUNT()
# ---------------------------------------------------
SELECT_COUNT()
{
	local row=$(
	(
		echo 'SET PAGESIZE 0'
		echo 'SET HEAD OFF'
		echo 'SET FEED OFF'
		echo "SELECT COUNT(*) FROM $TBL;"
	) | $SQLPLUS | sed -e 's/^[ \t]*//' -e 's/[ \t]$//')
	echo $row
}


# ---------------------------------------------------
# FUNCTION SELECT MAX()
# ---------------------------------------------------
SELECT_MAX()
{
	local max=$(
	(	
		echo 'SET PAGESIZE 0'
		echo 'SET HEAD OFF'
		echo 'SET FEED OFF'
		echo "SELECT MAX(A) FROM $TBL;"
	) | $SQLPLUS | sed -e 's/^[ \t]*//' -e 's/[ \t]$//')
	echo $max
}


# ---------------------------------------------------
# FUNCTION INSERT TABLE
# ---------------------------------------------------
INSERT_TABLE()
{
	local max=$(SELECT_MAX) && max=$((++max))
	local val=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9#!%' | fold -w 10 | head -n 1)
	# INSER STATEMENT 
	local SQL="INSERT INTO $TBL(A, B) VALUES ($max, '$val');"
	logging "${FUNCNAME[0]}" "$SQL"
	echo "$SQL"; echo "COMMIT;"
	return
}


# ---------------------------------------------------
# FUNCTION DELETE TABLE
# ---------------------------------------------------
DELETE_TABLE()
{
	local row=$(SELECT_COUNT)
	local num=$(echo $(($RANDOM % $row)))
	# DELETE STATEMENT
	local SQL="DELETE FROM $TBL WHERE A = $num;"
	logging "${FUNCNAME[0]}" "$SQL"
	echo "$SQL"; echo "COMMIT;"
	return
}


# ---------------------------------------------------
# FUNCTION UPDATE TABLE
# ---------------------------------------------------
UPDATE_TABLE()
{
	local row=$(SELECT_COUNT)
	local num=$(echo $(($RANDOM % $row)))
	local val=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9#!%' | fold -w 10 | head -n 1)
	# UPDATE STATEMENT
	local SQL="UPDATE $TBL SET B = '$val' WHERE A = $num;"
	logging "${FUNCNAME[0]}" "$SQL"
	echo "$SQL"; echo "COMMIT;"
	return
}


# ---------------------------------------------------
# FUNCTION SELECT TABLE
# ---------------------------------------------------
SELECT_TABLE()
{
	local row=$(SELECT_COUNT)
	local rate=${1:-10}
	local num=$(echo $(($RANDOM % $row)))

	local SQL=" "
	if test $(($RANDOM % rate)) -le 1; then
		SQL="SELECT * FROM $TBL;"
		logging "${FUNCNAME[0]}" "$SQL"; echo "$SQL"
	else
		SQL="SELECT * FROM $TBL WHERE A = $num;"
		logging "${FUNCNAME[0]}" "$SQL"; echo "$SQL"
	fi
	return
}


# ---------------------------------------------------
# Main
# ---------------------------------------------------

lockfile=/tmp/$(echo $0 | sed -e 's/\.sh//').loc
test -f "$lockfile" && exit 1
echo $$ > "$lockfile"


trap 'rm -fr "$lockfile"; exit 1'  1 2 3 15

# Initialize
DROP_TABLE
CREATE_TABLE

# Main Loop
while :
do
	_count=$(($RANDOM % 10)) 
    test "$_count" -eq 0 && DELETE_TABLE
    test "$_count" -eq 1 && UPDATE_TABLE
    test "$_count" -ge 2 -a "$_count" -le 7 && INSERT_TABLE
    test "$_count" -ge 8 -a "$_count" -le 9 && SELECT_TABLE

    sleep "$SLP"
done | $SQLPLUS

exit 0