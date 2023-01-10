-- 2022-08-21
create table earnings (
    id serial PRIMARY KEY,
    institution_id varchar not null references institutions on DELETE CASCADE,
    created timestamp default now(),
    value numeric not null,
    amount numeric not null,
    total numeric not null,
    currency varchar not null,
    rate numeric default 1,
    details varchar
);
