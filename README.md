# youtrack-to-slack

youtrack-to-slack.sh reads your Youtrack RSS feed and submits new tickets to slack via incoming webhooks.

**Please note:** This script is pretty hacky, but works fine under Mac OSX 10.10 and Linux and Youtrack 6.0

### configure Youtrack URL

Set the URL to your Youtrack instance. Make sure it ends with `/_rss_issues`

```
YT_URL="YT_URL=http://example.com/_rss/issues"
```

Set the username and password for Youtrack authorization. `/_rss_issues`

```
YT_USER="username"
```

```
YT_PASS="password"
```
