# dvl-exchange
Exchange registry for asset transactions.

## links
* https://www.yahoofinanceapi.com/
* https://currencyscoop.com/code-samples

# Cron Sync
Example for using `cron` to automatically sync values and create historical data from desired tickers:
```bash
0 10-18 * * 1-5 env USER=$LOGNAME $HOME/git/dvl-exchange/snapshot.sh >> /tmp/general.log
```

It will get prices from all the tickers you registered from 10 am to 18 am, on weekdays.