-- https://aws.amazon.com/blogs/database/multi-tenant-data-isolation-with-postgresql-row-level-security/
-- TODO pool partitionaing

--/
create table tickers (
    id serial primary key,
    name varchar not null unique,
    kind varchar,
    created timestamp default now(),
    public boolean not null default true,
    value numeric default 0,
    score numeric,
    currency varchar,
    tax_id varchar
);

create table exchanges (
    id serial primary key,
    name varchar not null,
    created timestamp default now()
);

create table assets (
    id serial PRIMARY KEY,
    ticker_id bigint references tickers,
    amount numeric default 0,
    created timestamp default now(),
    currency varchar not null default 'undefined',
    cost numeric default 0,
    value numeric default 0
);

create table asset_ops (
    id serial PRIMARY KEY,
    asset_id bigint not null references assets on DELETE CASCADE,
    kind varchar not null check(kind in ('BUY', 'SELL')),
    amount numeric not null,
    price numeric not null,
    currency varchar not null,
    institution varchar,
    rate numeric default 1,
    created timestamp default now(),
    simulation boolean not null default false
);

create table snapshots (
    id serial PRIMARY KEY,
    ticker_id bigint not null references tickers on DELETE CASCADE,
    created timestamp default now(),
    price numeric not null,
    currency varchar not null
);

create table dividends (
    id serial PRIMARY KEY,
    ticker_id bigint not null references tickers on DELETE CASCADE,
    created timestamp default now(),
    value numeric not null,
    amount numeric not null,
    total numeric not null,
    currency varchar not null,
    rate numeric default 1
);

create table loans (
    id serial PRIMARY KEY,
    ticker_id bigint not null references tickers on DELETE CASCADE,
    created timestamp default now(),
    amount numeric not null,
    total numeric not null,
    currency varchar not null,
    rate numeric default 1
);

create table stores (
    id serial PRIMARY KEY,
    created timestamp default now(),
    name varchar not null,
    category varchar,
    extra jsonb default '{}',
    description varchar
);

create table products (
    id serial PRIMARY KEY,
    created timestamp default now(),
    name varchar not null,
    brand varchar,
    tags varchar,
    ocr_tags varchar,
    market_id bigint,
    description varchar,
    weight numeric not null default 1,
    extra jsonb not null default '{}',
    recurring integer,
    product_type integer not null default 0
);

-- TODO create table product_type
-- 0: uncategorized
-- 1: fee

create table product_ops (
    id serial PRIMARY KEY,
    product_id bigint not null REFERENCES products on DELETE CASCADE,
    store_id bigint not null REFERENCES stores on DELETE CASCADE,
    created timestamp default now(),
    price numeric not null,
    amount numeric not null default 1,
    currency varchar,
    hidden boolean not null default false,
    tags varchar,
    simulation boolean not null default false
);

create table institutions (
    id varchar PRIMARY KEY,
    public_id varchar,
    created timestamp default now(),
    extra jsonb default '{}'
);

create table earnings (
    id serial PRIMARY KEY,
    institution_id varchar not null references institutions on DELETE CASCADE,
    created timestamp default now(),
    value numeric not null,
    amount numeric not null,
    total numeric not null,
    currency varchar not null,
    rate numeric default 1
);

create table index_snapshots (
    index_id integer not null,
    index_name varchar not null,
    created date default now()::date,
    price numeric not null,
    currency varchar not null,
    PRIMARY KEY(index_id, created)
);

-- region specific: BR
create table br_simples_nacional (
    id serial PRIMARY KEY,
    modified timestamp default now(),
    cut numeric not null,
    tax numeric not null,
    deduction numeric not null
);

insert into br_simples_nacional (cut, tax, deduction) values 
(180000, 6, 0),
(360000.00, 11.2, 9360.00),
(720000.00, 13.5, 17640.00),
(1800000.00, 16.0, 35640.00),
(3600000.00, 21.0, 125640.00),
(4800000.00, 33.0, 648000.00)
;

--/
insert into tickers (name) values ('DVLCUBE');

--/
CREATE OR REPLACE FUNCTION price(tickerId BIGINT)
RETURNS NUMERIC AS $f$
DECLARE
  _price numeric;
BEGIN
  select price from snapshots where ticker_id=tickerId 
  order by id desc 
  limit 1 
  into _price;
  RETURN _price;
END;
$f$ LANGUAGE plpgsql;
--/
CREATE OR REPLACE FUNCTION price(tickerId BIGINT, d date)
RETURNS NUMERIC AS $f$
DECLARE
  _price numeric;
BEGIN
  select price from snapshots 
  where ticker_id=tickerId
  and created < (d+interval '1 day')
  order by id desc 
  limit 1 
  into _price;
  RETURN _price;
END;
$f$ LANGUAGE plpgsql;
--/ e.g., percentage_diff(200, 100) => 100%
CREATE OR REPLACE FUNCTION percentage_diff(a numeric, b numeric)
RETURNS NUMERIC AS $f$
BEGIN
  RETURN round((a-b)*100/b, 2);
END;
$f$ LANGUAGE plpgsql;
--/ e.g., percentage(100, 30%) => 30
CREATE OR REPLACE FUNCTION percentage(a numeric, b numeric)
RETURNS NUMERIC AS $f$
BEGIN
  RETURN round((b*a) / 100, 2);
END;
$f$ LANGUAGE plpgsql;
--/
CREATE OR REPLACE FUNCTION recalculate_assets()
RETURNS NUMERIC AS $f$
DECLARE
  rows_affected integer;
BEGIN
  update assets asset 
  set cost = sop.price_sum
  from (
    select op.asset_id, sum(op.price) as price_sum
    from asset_ops op
    where op.simulation is false
    group by op.asset_id
  ) as sop
  where sop.asset_id = asset.id;

  GET DIAGNOSTICS rows_affected = ROW_COUNT;
  RETURN rows_affected;
END;
$f$ LANGUAGE plpgsql;
--/
CREATE OR REPLACE FUNCTION last_buy(tickerId BIGINT)
RETURNS NUMERIC AS $f$
DECLARE
  _price numeric;
BEGIN
  select round(op.price/op.amount, 2)
  from asset_ops op 
  join assets asset on asset.id=op.asset_id 
  join tickers ticker on ticker.id=asset.ticker_id 
  where ticker.id=tickerId
  order by op.id desc
  limit 1
  into _price;
  RETURN _price;
END;
$f$ LANGUAGE plpgsql;
--/
CREATE OR REPLACE FUNCTION avg_buy(tickerId BIGINT)
RETURNS NUMERIC AS $f$
DECLARE
  _price numeric;
BEGIN
  select round(avg(history.price/history.amount), 2) from (
    select op.price, op.amount 
    from asset_ops op 
    join assets asset on asset.id=op.asset_id 
    join tickers ticker on ticker.id=asset.ticker_id 
    where ticker.id=tickerId
    order by op.id desc
    limit 12
  ) history
  into _price;
  RETURN _price;
END;
$f$ LANGUAGE plpgsql;
--/