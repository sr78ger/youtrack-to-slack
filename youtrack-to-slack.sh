#!/bin/sh
if [ "$#" -eq 0 ];then
    DIR=$( cd "$( dirname "$0" )" && pwd )
    CONFIG=${DIR}/settings.sh
    else
    CONFIG=$1
fi
source $CONFIG
# --- define files for DB and cookie storage --
DB=${DATA_DIR}/youtrack.sqlite3
COOKIES=${DATA_DIR}/youtrack.cookies
TABLE=tickets
## -- setup youtrack URLs --
YT_URL_LOGIN="${YT_BASE_URL}/rest/user/login"
YT_URL_FEED="${YT_BASE_URL}/_rss/issues"
YT_URL_ISSUE="${YT_BASE_URL}/rest/issue/%issue%"
## -- check for DB file --
if [ ! -e "$DB" ] ; then
    touch "$DB" 2&>1
fi

if [ ! -w "$DB" ] ; then
    echo "cannot create database $DB"
    exit 1
fi
rm -f $COOKIES
# -- get cookie from youtrack --
RET=$(curl -s $YT_URL_LOGIN -c $COOKIES -H"Content-type: application/x-www-form-urlencoded" -d"login=${YT_USER}&password=${YT_PASS}")
if [ "$RET" != "<login>ok</login>" ]; then
    echo "authentication failed, got '$RET' ($?) after $YT_URL_LOGIN"
    exit 1
fi
if [ ! -e "$COOKIES" ] ; then
    echo "cookies file $COOKIES missing"
    exit 1
fi
# -- setup slack payload --
SLACK_PAYLOAD='{"channel": "#%chan%", "username": "%user%", "text": "%msg%", "icon_emoji": "%emoji%"}'
SLACK_PAYLOAD=${SLACK_PAYLOAD/\%chan\%/$SLACK_CHANNEL}
SLACK_PAYLOAD=${SLACK_PAYLOAD/\%user\%/$SLACK_USER}
SLACK_PAYLOAD=${SLACK_PAYLOAD/\%emoji\%/$SLACK_EMOJI}
# -- check for OSX/FreeBSD --
UNAME=$(uname)
IS_OSX=0
if [ "$UNAME" == "Darwin" ]; then
   IS_OSX=1
fi
#sqlite3 $DB  "drop table $TABLE;"
sqlite3 $DB  "create table if not exists $TABLE (id TEXT PRIMARY KEY, title TEXT, link TEXT, pubepoch INTEGER, updatedepoch INTEGER, user TEXT, userid TEXT, state TEXT, updater TEXT, updaterfullname TEXT, reporter TEXT, reporterfullname TEXT, created INTEGER );"
RC=$?
if [ "$RC" -ne "0" ]; then
    echo "database failed: cannot create table $TABLE"
    exit 1
fi
curl -s --user "$YT_USER:$YT_PASS" $YT_URL_FEED 2>&1 | (
YT_TITLE=""
YT_PUB=""
YT_EPOCH=0
YT_LINK=""
YT_ID=""
while read LINE;
do
if [[ $LINE =~ ^\<title ]]; then
    YT_TITLE=$(echo "$LINE" | awk -v FS="(<title>|</title)" '{print $2}' )
    YT_ID=${YT_TITLE%%:*}
    YT_TITLE=${YT_TITLE#*:}
    YT_TITLE=$(echo "$YT_TITLE" | perl -n -mHTML::Entities -e ' ; print HTML::Entities::decode_entities($_) ;' | tr -d '"' | sed 's/^ *//' )
elif [[ $LINE =~ ^\<pubDate ]]; then
    YT_PUB=$(echo "$LINE" | awk -v FS="(<pubDate>[A-Za-z, ]+| UT</pubDate)" '{print $2}' )
    YT_PUB=${YT_PUB%%,*}
    if [ "$IS_OSX" -eq "1" ]; then
            YT_EPOCH=$(date -j -f '%d %b %Y %H:%M:%S' "$YT_PUB" +%s)
            YT_PUB=$(date -r $YT_EPOCH '+%Y/%m/%d %H:%M:%S')
    else
            YT_EPOCH=$(date --date "$YT_PUB" +%s)
            YT_PUB=$(date -d @${YT_EPOCH} '+%Y/%m/%d %H:%M:%S')
    fi
elif [[ $LINE =~ ^\<img ]]; then
    YT_IMG=$(echo "$LINE" | awk -v FS="(<img|>)" '{print $2}' )
    YT_USER=$(echo "$YT_IMG" | grep -o 'title=\".*\"' | cut -f 2 -d'"')
    YT_USERID=$(echo "$YT_USER" | cut -f2 -d'(' | tr -d ')')
    YT_USER=${YT_USER%\(*}
    YT_USER=$(echo "$YT_USER" | sed -e 's/^ *//' -e 's/ *$//' )
elif [[ $LINE =~ ^\<link ]]; then
    YT_LINK=$(echo "$LINE" | awk -v FS="(<link>|</link>)" '{print $2}' )
fi
if [[ $LINE =~ ^\</item\> ]]; then
    URL=${YT_URL_ISSUE/\%issue\%/$YT_ID}
    YT_STATE=""
    YT_UPDATED=""
    YT_UPDATED_EPOCH=""
    LINE_NAME=""
    YT_UPDATER_NAME=""
    YT_UPDATER_FULLNAME=""
    YT_REPORTER_NAME=""
    YT_REPORTER_FULLNAME=""
    YT_CREATED=""
    if [ "$DEBUG" -eq "1" ]; then
     	echo "requesting ticket $YT_ID details via REST API: $URL"
    fi
    curl -s -b $COOKIES $URL | xmllint --format - | ( while read LINE;
    do
        LINE_PLAIN=$(echo "$LINE" | head -n1 | cut -f2 -d'>' | cut -f1 -d'<')
        if [[ "$LINE_NAME" == "updated" ]]; then
            YT_UPDATED_EPOCH=$(echo "$LINE" | sed 's/[^0-9]//g' )
            YT_UPDATED_EPOCH=$((YT_UPDATED_EPOCH/1000))
            if [ "$IS_OSX" -eq "1" ]; then
                YT_UPDATED=$(date -r $YT_UPDATED_EPOCH '+%Y/%m/%d %H:%M:%S')
                else
                YT_UPDATED=$(date -d @${YT_UPDATED_EPOCH} '+%Y/%m/%d %H:%M:%S')
            fi
        elif [[ "$LINE_NAME" == "created" ]]; then
            YT_CREATED=$(echo "$LINE" | sed 's/[^0-9]//g' )
        elif [[ "$LINE_NAME" == "reporterName" ]]; then
            YT_REPORTER_NAME=$LINE_PLAIN
        elif [[ "$LINE_NAME" == "reporterFullName" ]]; then
            YT_REPORTER_FULLNAME=$LINE_PLAIN
        elif [[ "$LINE_NAME" == "updaterName" ]]; then
            YT_UPDATER_NAME=$LINE_PLAIN
        elif [[ "$LINE_NAME" == "updaterFullName" ]]; then
            YT_UPDATER_FULLNAME=$LINE_PLAIN
        elif [[ "$LINE_NAME" == "state" ]]; then
            YT_STATE=$LINE_PLAIN
        fi
        LINE_NAME=""
        if [[ $LINE =~ name\=\"State\" ]]; then
            LINE_NAME="state"
        fi
        if [[ $LINE =~ name\=\"created\" ]]; then
            LINE_NAME="created"
        fi
        if [[ $LINE =~ name\=\"reporterFullName\" ]]; then
            LINE_NAME="reporterFullName"
        fi
        if [[ $LINE =~ name\=\"reporterName\" ]]; then
            LINE_NAME="reporterName"
        fi
        if [[ $LINE =~ name\=\"updaterFullName\" ]]; then
            LINE_NAME="updaterFullName"
        fi
        if [[ $LINE =~ name\=\"updaterName\" ]]; then
            LINE_NAME="updaterName"
        fi
        if [[ $LINE =~ name\=\"updated\" ]]; then
            LINE_NAME="updated"
        fi
    done
    if [ "$DEBUG" -eq "1" ]; then
     	echo "checking if ticket with ID $YT_ID exists... (created=$YT_CREATED, reporterName=$YT_REPORTER_NAME, reporterFullname=$YT_REPORTER_FULLNAME, updaterName=$YT_UPDATER_NAME, updaterFullname=$YT_UPDATER_FULLNAME)"
    fi
    EXISTS=$(sqlite3 $DB  "select count(*) from $TABLE where id = '$YT_ID'";)
    if [ "$DEBUG" -eq "1" ]; then
     	echo "ticket $YT_ID... (exists=$EXISTS)"
    fi
    if [ "$EXISTS" -ne "1" ]; then
        SQL="insert into $TABLE ( id, title, link, pubepoch, updatedepoch, user, userid, state, reporter, reporterfullname, updater, updaterfullname, created ) values ( '$YT_ID', '$YT_TITLE', '$YT_LINK', '$YT_EPOCH', '$YT_UPDATED_EPOCH', '$YT_USER', '$YT_USERID', '$YT_STATE', '$YT_REPORTER_NAME', '$YT_REPORTER_FULLNAME', '$YT_UPDATER_NAME', '$YT_UPDATER_FULLNAME', '$YT_CREATED' );"
        if [ "$DEBUG" -eq "1" ]; then
     	echo "insert ticket $YT_ID: $SQL"
        fi
        sqlite3 $DB "$SQL"
        EXISTS=$(sqlite3 $DB  "select count(*) from $TABLE where id = '$YT_ID'";)
        if [ "$EXISTS" -ne "1" ]; then
 	   echo "ticket $YT_ID inserted, but reading failed"
	   exit 1
        fi
        COUNT=$((COUNT+1))
        if [ "$COUNT" -lt "$LIMIT" ]; then
            MESSAGE="New ticket from $YT_USER: $YT_ID: $YT_TITLE, $YT_LINK ($YT_PUB)"
            MESSAGE=$(echo $MESSAGE | sed 's/"/\"/g' | sed "s/'/\'/g" | tr '\n' ' ' | tr '\r' ' ' | tr -d '[' | tr -d ']' )
            PAYLOAD=${SLACK_PAYLOAD/\%msg\%/$MESSAGE}
	    if [ "$DEBUG" -eq "1" ]; then
		echo $PAYLOAD
    	    else
		        if [ "$CURL" -eq "1" ]; then
                RET=$(curl -s -d "payload=$PAYLOAD" $SLACK_URL)
                fi
      	        #echo "#${COUNT}: $RET: $PAYLOAD"
	    fi
        fi
    else
        UPDATED=$(sqlite3 $DB  "select updatedepoch from $TABLE where id = '$YT_ID';";)
	    RC=$?
	    echo "compare $UPDATED ($YT_ID) with $YT_UPDATED_EPOCH"
        if [ "$UPDATED" -lt "$YT_UPDATED_EPOCH" ] 2>/dev/null; then
	        if [ "$DEBUG" -eq "1" ]; then
		        echo "found an update for $YT_ID, $YT_UPDATED ($YT_UPDATED_EPOCH), got $UPDATED (RC=$RC)"
            fi
            sqlite3 $DB  "update $TABLE set updatedepoch = '$YT_UPDATED_EPOCH', state = '$YT_STATE', updater='$YT_UPDATER_NAME', updaterfullname='$YT_UPDATER_FULLNAME' where id = '$YT_ID';"
            COUNT=$((COUNT+1))
            if [ "$COUNT" -lt "$LIMIT" ]; then
                MESSAGE="Ticket $YT_ID updated by $YT_UPDATER_FULLNAME, state $YT_STATE, $YT_LINK"
                MESSAGE=$(echo $MESSAGE | sed 's/"/\"/g' | sed "s/'/\'/g" | tr '\n' ' ' | tr '\r' ' ' | tr -d '[' | tr -d ']' )
                PAYLOAD=${SLACK_PAYLOAD/\%msg\%/$MESSAGE}
		        if [ "$DEBUG" -eq "1" ]; then
			        echo $PAYLOAD
		        else if [ "$CURL" -eq "1" ]; then
    	                RET=$(curl -s -d "payload=$PAYLOAD" $SLACK_URL)
                     fi
		        fi
            fi
        else
	        if [ "$DEBUG" -eq "1" ]; then
		        echo "ticket $YT_ID not updated"
            fi
        fi
    fi
    )
fi
done
)
echo "done"
#sqlite3 $DB "select * from $TABLE;"

