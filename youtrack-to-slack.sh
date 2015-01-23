#!/bin/sh
SLACK_URL="https://hooks.slack.com/services/XXXXXXXXX/XXXXXXXXX/XXXXXXXXXXXXXXXXXXXXXXXX"
SLACK_CHANNEL="ticket"
SLACK_USER="slackuser"
SLACK_EMOJI=":hear_no_evil"
YT_BASE_URL="http://youtrack.url"
YT_USER="username"
YT_PASS="password"
LIMIT=10
DATA_DIR=~
# --- define files for DB and cookie storage --
DB=${DATA_DIR}/youtrack.sqlite3
COOKIES=${DATA_DIR}/youtrack.sqlite3
TABLE=tickets
## -- setup youtrack URLs --
YT_URL_LOGIN="${YT_BASE_URL}/rest/user/login"
YT_URL_FEED="${YT_BASE_URL}/_rss/issues"
YT_URL_ISSUE="${YT_BASE_URL}rest/issue/%issue%"
## -- check for DB file --
if [ ! -e "$DB" ] ; then
    touch "$DB" 2&>1
fi

if [ ! -w "$DB" ] ; then
    echo "cannot create database $DB"
    exit 1
fi
# -- get cookie from youtrack --
RET=$(curl -s $YT_URL_LOGIN --cookie $COOKIES -H"Content-type: application/x-www-form-urlencoded" -d"login=${YT_USER}&password=${YT_PASS}")
if [ "$RET" != "<login>ok</login>" ]; then
    echo "authentication failed: $RET"
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
sqlite3 $DB  "create table if not exists $TABLE (id TEXT PRIMARY KEY, title TEXT, link TEXT, pubepoch INTEGER, user TEXT, userid TEXT );"
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
    echo "'$YT_USER' from '$YT_USERID'"
elif [[ $LINE =~ ^\<link ]]; then
    YT_LINK=$(echo "$LINE" | awk -v FS="(<link>|</link>)" '{print $2}' )
fi
if [[ $LINE =~ ^\</item\> ]]; then
    EXISTS=$(sqlite3 $DB  "select count(*) from $TABLE where id = '$YT_ID'";)
    if [ "$EXISTS" -ne "1" ]; then
        sqlite3 $DB  "insert into $TABLE ( id, title, link, pubepoch, user, userid ) values ( '$YT_ID', '$YT_TITLE', '$YT_LINK', '$YT_EPOCH', '$YT_USER', '$YT_USERID' );"
        COUNT=$((COUNT+1))
        if [ "$COUNT" -lt "$LIMIT" ]; then
        MESSAGE="Ticket from $YT_USER: $YT_ID: $YT_TITLE, $YT_LINK ($YT_PUB)"
        MESSAGE=$(echo $MESSAGE | sed 's/"/\"/g' | sed "s/'/\'/g" | tr '\n' ' ' | tr '\r' ' ' | tr -d '[' | tr -d ']' )
        PAYLOAD=${SLACK_PAYLOAD/\%msg\%/$MESSAGE}
        RET=$(curl -s -d "payload=$PAYLOAD" $SLACK_URL)
        #echo "#${COUNT}: $RET: $PAYLOAD"
        fi
    fi
fi
done
)
#sqlite3 $DB "select * from $TABLE;"