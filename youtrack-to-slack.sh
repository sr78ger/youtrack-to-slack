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
    echo "authentication failed, got '$RET' after $YT_URL_LOGIN"
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
sqlite3 $DB  "create table if not exists $TABLE (id TEXT PRIMARY KEY, title TEXT, link TEXT, pubepoch INTEGER, updatedepoch INTEGER, user TEXT, userid TEXT, state TEXT );"
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
        elif [[ "$LINE_NAME" == "state" ]]; then
            YT_STATE=$LINE_PLAIN
        fi
        LINE_NAME=""
        if [[ $LINE =~ name\=\"State\" ]]; then
            LINE_NAME="state"
        fi
        if [[ $LINE =~ name\=\"updated\" ]]; then
            LINE_NAME="updated"
        fi
    done
    #echo "$YT_ID state=$YT_STATE"
    EXISTS=$(sqlite3 $DB  "select count(*) from $TABLE where id = '$YT_ID'";)
    if [ "$EXISTS" -ne "1" ]; then
        sqlite3 $DB  "insert into $TABLE ( id, title, link, pubepoch, updatedepoch, user, userid, state ) values ( '$YT_ID', '$YT_TITLE', '$YT_LINK', '$YT_EPOCH', '$YT_UPDATED_EPOCH', '$YT_USER', '$YT_USERID', '$YT_STATE' );"
        COUNT=$((COUNT+1))
        if [ "$COUNT" -lt "$LIMIT" ]; then
            MESSAGE="New ticket from $YT_USER: $YT_ID: $YT_TITLE, $YT_LINK ($YT_PUB)"
            MESSAGE=$(echo $MESSAGE | sed 's/"/\"/g' | sed "s/'/\'/g" | tr '\n' ' ' | tr '\r' ' ' | tr -d '[' | tr -d ']' )
            PAYLOAD=${SLACK_PAYLOAD/\%msg\%/$MESSAGE}
            RET=$(curl -s -d "payload=$PAYLOAD" $SLACK_URL)
            #echo "#${COUNT}: $RET: $PAYLOAD"
        fi
    else
        UPDATED=$(sqlite3 $DB  "select count(*) from $TABLE where id = '$YT_ID' AND updatedepoch < '$YT_UPDATED_EPOCH'";)
        if [ "$UPDATED" -ne "1" ]; then
            sqlite3 $DB  "update $TABLE set updatedepoch = '$YT_UPDATED_EPOCH', state = '$YT_STATE' where id = '$YT_ID');"
            COUNT=$((COUNT+1))
            if [ "$COUNT" -lt "$LIMIT" ]; then
                MESSAGE="Updated ticket from $YT_USER ($YT_STATE): $YT_ID: $YT_TITLE, $YT_LINK ($YT_UPDATED)"
                MESSAGE=$(echo $MESSAGE | sed 's/"/\"/g' | sed "s/'/\'/g" | tr '\n' ' ' | tr '\r' ' ' | tr -d '[' | tr -d ']' )
                PAYLOAD=${SLACK_PAYLOAD/\%msg\%/$MESSAGE}
                RET=$(curl -s -d "payload=$PAYLOAD" $SLACK_URL)
                #echo "#${COUNT}: $RET: $PAYLOAD"
            fi
        fi
    fi
    )
fi
done
)
echo "done"
#sqlite3 $DB "select * from $TABLE;"