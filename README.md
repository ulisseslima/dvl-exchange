# dvl-exchange
Exchange registry for asset transactions.

# Installing
You need to have a running instance of PostgreSQL, capable of connecting via `psql`. The user defaults to `$USER`. You can override default values by creating a `~/.dvl-exchange/config` file.

```bash
git clone https://github.com/ulisseslima/dvl-exchange
cd dvl-exchange
./setup
```

# Usage
Note: tickers have to use the same name used by Yahoo Finance API:
```bash
dvlx-new-op BUY 10 SPHQ 531.70 USD '2022-01-11'
dvlx-new-op BUY 9 GGRC11.SA 1051.11 BRL '2022-01-3'
```
The `price` value (arg 4) refers to the price of the whole operation.

View your latest ops:
```bash
dvlx-select-ops
```

View your current consolidated position:
```bash
dvlx-position
```

## Syncing with CEI
CEI doesn't have a public API, but you can use the script below by manually defining `CEI_KEY_GUID` and `CEI_KEY_BEARER` in your local config file (`~/.dvl-exchange/config`). You can get those values by logging-in in a browser and inspecting network requests. 

```bash
dvlx-sync-cei
```

# APIs used
* https://www.yahoofinanceapi.com/
* https://currencyscoop.com/code-samples

## Cron Sync
Example for using `cron` to automatically sync values and create historical data from desired tickers:
```bash
0 10-18 * * 1-5 env USER=$LOGNAME $HOME/git/dvl-exchange/snapshot.sh >> /tmp/general.log
```

It will get prices from all the tickers you registered from 10 am to 18 am, on weekdays.

# Useful Links
* https://statusinvest.com.br/fundos-imobiliarios/alzr11
* https://money.usnews.com/funds/etfs/global-real-estate/vanguard-global-ex-us-real-est-etf/vnqi