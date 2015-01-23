# youtrack-to-slack

youtrack-to-slack.sh reads your Youtrack RSS feed and submits new tickets to slack via incoming webhooks.

**Please note:** This script is pretty hacky, but works fine under Mac OSX 10.10 and Linux and Youtrack 6.0

youtrack-to-slack.sh requires no special programs on OSX or Linux, just ``curl``, ``awk``, ``sed``, ``tr``, ``sqlite3``, ``xmllint` and ``perl`` for html entity decode.

### configure Slack

Define the SLACK_URL with the URL you received after defining a Slack Incoming WebHook.

```shell
SLACK_URL="https://hooks.slack.com/services/XXXXXXXXX/XXXXXXXXX/XXXXXXXXXXXXXXXXXXXXXXXX"
```

Set the channel you want this script to post to.

```shell
SLACK_CHANNEL="ticket"
```

Set the name you want the script to use when posting messages.
```shell
SLACK_USER="slackuser"
```

### configure Youtrack

Set the base URL to your Youtrack instance. 

```shell
YT_BASE_URL="http://example.com"
```

Set the username and password for Youtrack authorization. `/_rss_issues`

```shell
YT_USER="username"
```

```shell
YT_PASS="password"
```

### configure sqlite database and limit

Set the path where the database should be created.

```shell
DB="/opt/youtrack-to-slack.sqlite3"
```

Define the maximum number of notifications to send.

```shell
LIMIT=10
```
