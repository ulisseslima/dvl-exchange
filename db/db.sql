-- https://aws.amazon.com/blogs/database/multi-tenant-data-isolation-with-postgresql-row-level-security/
-- TODO pool partitionaing

create table tickers (
    id serial primary key,
    name varchar not null unique,
    kind varchar,
    created timestamp default now(),
    public boolean not null default true
);

create table exchanges (
    id serial primary key,
    name varchar not null,
    created timestamp default now()
);

create table assets (
    id serial PRIMARY KEY,
    ticker_id bigint references tickers,
    amount real default 0,
    created timestamp default now(),
    currency varchar not null default 'undefined',
    cost real default 0
);

create table asset_ops (
    id serial PRIMARY KEY,
    asset_id bigint not null references assets on DELETE CASCADE,
    kind varchar not null check(kind in ('BUY', 'SELL')),
    amount real not null,
    price real not null,
    currency varchar not null,
    institution varchar,
    rate real default 0,
    created timestamp default now()
);

create table snapshots (
    id serial PRIMARY KEY,
    ticker_id bigint not null references tickers on DELETE CASCADE,
    created timestamp default now(),
    price real not null,
    currency varchar not null
);

insert into tickers (name) values ('DVLCUBE');