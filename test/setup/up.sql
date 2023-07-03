\set QUIET 'on'

create extension btree_gist;

create schema sample;

create table sample.s
    ( id                text not null
    , value             int not null
    , valid_period      int4range not null
    , system_period     int4range not null
    , primary key(id, valid_period)
    , exclude using gist (id with =, valid_period with &&)
    , exclude using gist (id with =, value with =, valid_period with -|-) );

create table sample.sp
    ( s_id              text not null
    , id                text not null
    , state             int not null
    , valid_period      int4range not null
    , primary key(s_id, id, valid_period)
    , exclude using gist(s_id with =, id with =, valid_period with &&)
    , exclude using gist(s_id with =, id with =, state with =, valid_period with -|-) );

create procedure sample.save_s
    ( s_id           sample.s.id%type
    , s_value        sample.s.value%type
    , s_valid_period sample.s.valid_period%type )
as $body$
declare
    r   sample.s;
    vps int4multirange;
    vp  sample.s.valid_period%type;
    t   int;
begin
    if isempty(s_valid_period) then
        raise exception 'empty valid time';
    end if;

    raise debug 'checking for overlaps: (%, %)', s_id, s_valid_period;
    for r in select id
                  , value
                  , valid_period
               from sample.s
              where id = s_id
                and valid_period && s_valid_period
    loop
        raise debug 'found overlapping record: (%, %, %)', r.id, r.value, r.valid_period;

        vps := r.valid_period::int4multirange - s_valid_period::int4multirange;
        raise debug 'vps: %', vps;

        raise debug 'deleting record by PK (%, %)', r.id, r.valid_period;
        delete from sample.s where id = r.id and valid_period = r.valid_period;

        if not isempty(vps) then
            foreach vp in array (select array_agg(x.*) from unnest(vps) x)
            loop
                if not isempty(vp) then
                    raise debug 'inserting unmatched part of overlapped record with period: (%, %, %)', r.id, r.value, vp;
                    insert into sample.s(id, value, valid_period) values(r.id, r.value, vp);
                end if;
            end loop;
        end if;
    end loop;

    raise debug 'checking for adjacency: (%, %, %)', s_id, s_value, s_valid_period;

    select range_agg(x.valid_period)
      into vps
      from (select s_valid_period as "valid_period"
             union all
            select valid_period
              from sample.s
             where id = s_id
               and value = s_value
               and valid_period -|- s_valid_period) x     ;

    raise debug 'vps: %', vps;

    if not isempty(vps) then
        foreach vp in array (select array_agg(x.*) from unnest(vps) x)
        loop
            raise debug 'vp: %', vp;

            raise debug 'deleting adjacents: (%, %, %)', s_id, s_value, s_valid_period;
            delete from sample.s where id = s_id and value = s_value and valid_period -|- s_valid_period;

            raise debug 'inserting consolidated record: (%, %, %)', s_id, s_value, vp;
            insert into sample.s(id, value, valid_period) values (s_id, s_value, vp);
            return;
        end loop;
    end if;

    raise debug 'inserting desired record: (%, %, %)', s_id, s_value, s_valid_period;
    insert into sample.s(id, value, valid_period) values(s_id, s_value, s_valid_period);
end; $body$ language plpgsql;

create procedure sample.save_sp
    ( sp_s_id         sample.sp.s_id%type
    , sp_id           sample.sp.id%type
    , sp_state        sample.sp.state%type
    , sp_valid_period sample.sp.valid_period%type )
as $body$
declare
    r   sample.sp;
    vps int4multirange;
    vp  sample.sp.valid_period%type;
begin
    if isempty(sp_valid_period) then
        raise exception 'empty valid time';
    end if;

    raise debug 'checking for overlaps: (%, %, %)', sp_s_id, sp_id, sp_valid_period;
    for r in select s_id
                  , id
                  , state
                  , valid_period
               from sample.sp
              where s_id = sp_s_id
                and id = sp_id
                and valid_period && sp_valid_period
    loop
        raise debug 'found overlapping record: (%, %, %, %)', r.s_id, r.id, r.state, r.valid_period;

        vps := r.valid_period::int4multirange - sp_valid_period::int4multirange;
        raise debug 'vps: %', vps;

        raise debug 'deleting record by PK (%, %, %)', r.s_id, r.id, r.valid_period;
        delete from sample.sp
              where s_id = r.s_id
                and id = r.id
                and valid_period = r.valid_period;

        if not isempty(vps) then
            foreach vp in array (select array_agg(x.*) from unnest(vps) x)
            loop
                if not isempty(vp) then
                    raise debug 'inserting unmatched part of overlapped record with period: (%, %, %, %)', r.s_id, r.id, r.state, vp;
                    insert into sample.sp(s_id, id, state, valid_period) values(r.s_id, r.id, r.state, vp);
                end if;
            end loop;
        end if;
    end loop;

    raise debug 'checking for adjacency: (%, %, %, %)', sp_s_id, sp_id, sp_state, sp_valid_period;

    select range_agg(x.valid_period)
      into vps
      from (select sp_valid_period as "valid_period"
             union all
            select valid_period
              from sample.sp
             where s_id = sp_s_id
               and id = sp_id
               and state = sp_state
               and valid_period -|- sp_valid_period) x;

    raise debug 'vps: %', vps;

    if not isempty(vps) then
        foreach vp in array (select array_agg(x.*) from unnest(vps) x)
        loop
            raise debug 'vp: %', vp;

            raise debug 'deleting adjacents: (%, %, %, %)', sp_s_id, sp_id, sp_state, sp_valid_period;
            delete from sample.sp
            where s_id = sp_s_id
              and id = sp_id
              and state = sp_state
              and valid_period -|- sp_valid_period;

            raise debug 'inserting consolidated record: (%, %, %, %)', sp_s_id, sp_id, sp_state, vp;
            insert into sample.sp(s_id, id, state, valid_period) values (sp_s_id, sp_id, sp_state, vp);
            return;
        end loop;
    end if;

    raise debug 'inserting desired record: (%, %, %, %)', sp_s_id, sp_id, sp_state, sp_valid_period;
    insert into sample.sp(s_id, id, state, valid_period) values(sp_s_id, sp_id, sp_state, sp_valid_period);
end; $body$ language plpgsql;

create or replace procedure sample.remove_sp
    ( filter          text
    , sp_valid_period sample.sp.valid_period%type )
as $body$
declare
    r   sample.sp;
    vps int4multirange;
    vp  sample.sp.valid_period%type;
begin
    raise debug 'sample.remove_sp(filter=%, sp_valid_period=%)', quote_literal(filter), quote_literal(sp_valid_period);

    if isempty(sp_valid_period) then
        raise exception 'empty valid time';
    end if;

    raise debug 'checking for overlaps: (%, %)', filter, sp_valid_period;
    for r in execute format($$select *
                                from sample.sp as "x"
                               where %s
                                 and x.valid_period && %s$$
                           , filter
                           , quote_literal(sp_valid_period))
    loop
        raise debug 'found overlapping record: (%, %, %, %)', r.s_id, r.id, r.state, r.valid_period;

        vps := r.valid_period::int4multirange - sp_valid_period::int4multirange;
        raise debug 'vps: %', vps;

        raise debug 'deleting record by PK (%, %, %)', r.s_id, r.id, r.valid_period;
        delete from sample.sp
              where s_id = r.s_id
                and id = r.id
                and valid_period = r.valid_period;

        if not isempty(vps) then
            foreach vp in array (select array_agg(x.*) from unnest(vps) x)
            loop
                raise debug 'inserting remaining part of overlapped record: (%, %, %, %)', r.s_id, r.id, r.state, vp;
                insert into sample.sp(s_id, id, state, valid_period) values(r.s_id, r.id, r.state, vp);
            end loop;
        end if;
    end loop;
end; $body$ language plpgsql;

create or replace procedure sample.remove_cascade_sp
    ( filter          text
    , sp_valid_period sample.s.valid_period%type )
as $body$
begin
    raise debug 'sample.remove_cascade_sp(filter=%, sp_valid_period=%)', quote_literal(filter), quote_literal(sp_valid_period);

    if isempty(sp_valid_period) then
        raise exception 'empty valid time';
    end if;

    call sample.remove_sp(filter, sp_valid_period);
end; $body$ language plpgsql;

create or replace procedure sample.remove_s
    ( filter         text
    , s_valid_period sample.s.valid_period%type )
as $body$
declare
    r   sample.s;
    vps int4multirange;
    vp  sample.s.valid_period%type;
begin
    raise debug 'sample.remove_s(filter=%, s_valid_period=%)', quote_literal(filter), quote_literal(s_valid_period);

    if isempty(s_valid_period) then
        raise exception 'empty valid time';
    end if;

    raise debug 'checking for overlaps: (%, %)', filter, s_valid_period;
    for r in execute format($$select x.id
                                   , x.value
                                   , x.valid_period
                                from sample.s as "x"
                               where %s
                                 and x.valid_period && %s$$
                           , filter
                           , quote_literal(s_valid_period))
    loop
        raise debug 'found overlapping record: (%, %, %)', r.id, r.value, r.valid_period;

        vps := r.valid_period::int4multirange - s_valid_period::int4multirange;
        raise debug 'vps: %', vps;

        raise debug 'deleting record by PK (%, %)', r.id, r.valid_period;
        delete from sample.s
              where id = r.id
                and valid_period = r.valid_period;

        if not isempty(vps) then
            foreach vp in array (select array_agg(x.*) from unnest(vps) x)
            loop
                raise debug 'inserting remaining part of overlapped record: (%, %, %)', r.id, r.value, vp;
                insert into sample.s(id, value, valid_period) values(r.id, r.value, vp);
            end loop;
        end if;
    end loop;
end; $body$ language plpgsql;

create or replace procedure sample.remove_cascade_s
    ( filter         text
    , s_valid_period sample.s.valid_period%type )
as $body$
declare
    r sample.sp;
begin
    raise debug 'sample.remove_cascade_s(filter=%, s_valid_period=%)', quote_literal(filter), quote_literal(s_valid_period);

    if isempty(s_valid_period) then
        raise exception 'empty valid time';
    end if;

    call sample.remove_cascade_sp(format('x.s_id in (select id from sample.s as x where %s and x.valid_period && %s)', filter, quote_literal(s_valid_period)), s_valid_period);

    call sample.remove_s(filter, s_valid_period);
end; $body$ language plpgsql;

create or replace function sample.check_fk_s_sp()
   returns trigger
   language plpgsql
as $body$
declare
  r   sample.sp;
  rs  sample.sp[] default '{}';
begin
  for r in with x as (select id
                           , range_agg(valid_period) as "valid_period"
                        from sample.s
                       group by id)
         select sp.*
           from sample.sp as sp, x
          where x.id = sp.s_id
            and not x.valid_period @> sp.valid_period
          union all
         select sp.*
           from sample.sp as sp
      left join x on x.id = sp.s_id
          where x.id is null
  loop
      rs := rs || r;
  end loop;

  if array_length(rs, 1) <> 0 then
    raise exception 'invalid state, violating records on SP: %', rs;
  end if;

  return new;
end; $body$;

create constraint trigger sp_check_fk_s
    after insert or update or delete on sample.sp
    initially deferred
    for each row
    execute function sample.check_fk_s_sp();

create constraint trigger s_check_fk_sp
    after insert or update or delete on sample.s
    initially deferred
    for each row
    execute function sample.check_fk_s_sp();

create schema bitemporal;

create table bitemporal.foreign_keys
    ( parent            regclass not null
    , parent_columns    name[]   not null
    , child             regclass not null
    , child_columns     name[]   not null
    , primary key(parent, child, child_columns) );

insert into bitemporal.foreign_keys(parent, parent_columns, child, child_columns)
values ('sample.s', '{id}', 'sample.sp', '{s_id}');

create schema sample_history;

create table sample_history.s (like sample.s);

create table sample_history.sp (like sample.sp);

create or replace function sample_history.truncate_history()
returns trigger
language plpgsql
as $body$
begin
    execute format('truncate %s_history.%s', tg_table_schema, tg_table_name);
    return null;
end; $body$;

create sequence sample_history.system_time increment by 1
    minvalue 0
    start  with 0;

create or replace function sample_history.log_history_s()
returns trigger
language plpgsql
as $body$
declare
    t int;
begin
    select last_value into t from sample_history.system_time;
    raise debug 'sample_history.log_history_s()@%', t;

    insert into sample_history.s(id, value, valid_period, system_period)
    select id
         , value
         , valid_period
         , int4range( lower(system_period)
                    , (select nextval('sample_history.system_time')::int) )
      from old_table;

    return null;
end; $body$;

create trigger s_history_upt
    after update on sample.s
    referencing old table as old_table
    for each statement
    execute function sample_history.log_history_s();

create trigger s_history_del
    after delete on sample.s
    referencing old table as old_table
    for each statement
    execute function sample_history.log_history_s();

create trigger s_truncate_history
    after truncate on sample.s
    for each statement
    execute function sample_history.truncate_history();

create or replace function sample_history.set_system_period_s()
returns trigger
language plpgsql
as $body$
declare
    t int;
begin
    select last_value into t from sample_history.system_time;
    raise debug 'sample_history.set_system_period_s(%)@%', new, t;

    select int4range((select nextval('sample_history.system_time')::int), null)
    into new.system_period;

    return new;
end; $body$;

create trigger s_system_time_before
    before insert or update on sample.s
    for each row
    execute function sample_history.set_system_period_s();

create type bitemporal.range_type
    as enum ( 'integer'
            , 'bigint'
            , 'numeric'
            , 'timestamp'
            , 'timestamptz'
            , 'date' );

create or replace function bitemporal.get_range_type
    ( range_type bitemporal.range_type )
    returns text
    language sql
    immutable
    returns null on null input
    return case range_type
               when 'integer'      then 'int4range'
               when 'bigint'       then 'int8range'
               when 'numeric'      then 'numrange'
               when 'timestamp'    then 'tsrange'
               when 'timestamptz'  then 'tstzrange'
               when 'date'         then 'daterange'
           end;

create or replace function bitemporal.get_multirange_type
    ( range_type bitemporal.range_type )
    returns text
    language sql
    immutable
    returns null on null input
    return case range_type
                when 'integer'      then 'int4multirange'
                when 'bigint'       then 'int8multirange'
                when 'numeric'      then 'nummultirange'
                when 'timestamp'    then 'tsmultirange'
                when 'timestamptz'  then 'tstzmultirange'
                when 'date'         then 'datemultirange'
              end;

create table bitemporal.params
    ( id                            boolean generated always as (true) stored unique --make this table accept only one row :)
    , valid_time_name               name
    , valid_time_type               bitemporal.range_type not null
    , valid_time_range              text not null generated always as (bitemporal.get_range_type(valid_time_type)) stored
    , valid_time_multirange         text not null generated always as (bitemporal.get_multirange_type(valid_time_type)) stored
    , system_time_name              name
    , system_time_type              bitemporal.range_type not null
    , system_time_range             text not null generated always as (bitemporal.get_range_type(system_time_type)) stored
    , system_time_multirange        text not null generated always as (bitemporal.get_multirange_type(system_time_type)) stored
    , system_time_current_time_fn   text not null
    , debug                         boolean not null );

insert into bitemporal.params(valid_time_name, valid_time_type, system_time_name, system_time_type, system_time_current_time_fn, debug)
values ('valid_period', 'integer', 'system_period', 'integer', '', false);

create or replace function bitemporal.get_params()
returns bitemporal.params
language plpgsql
stable
as $body$
declare
    p   bitemporal.params;
begin
    select *
      into p
      from bitemporal.params;

    if not found then
        raise exception 'empty table bitemporal.params';
    end if;

    return p;
end; $body$;

create type bitemporal.table_error
    as enum ( 'table-not-found'
            , 'missing-valid-time'
            , 'wrong-valid-time-range-type'
            , 'nullable-valid-time'
            , 'missing-system-time'
            , 'wrong-system-time-range-type'
            , 'nullable-system-time'
            , 'missing-primary-key'
            , 'missing-valid-time-on-primary-key'
            , 'invalid-table-type' -- TODO information_schema.tables.type
            -- TODO: foreign key erros?
            );

create or replace function bitemporal.sort_array(anyarray)
returns anyarray
language sql
immutable
as $$
    select array(select unnest($1) order by 1)
$$;

create or replace function bitemporal.overlap_operator_for(name)
returns name
language sql
stable
as $$
    with p as (select valid_time_name
                 from bitemporal.params)
    select case $1
             when valid_time_name then '&&'
             else '='
           end
      from p
$$;

create or replace function bitemporal.adjacency_operator_for(name)
returns name
language sql
stable
as $$
    with p as (select valid_time_name
                 from bitemporal.params)
    select case $1
             when valid_time_name then '-|-'
             else '='
           end
      from p
$$;

create or replace function bitemporal.validate_overlap_constraint
    ( relid regclass )
returns table
    ( namespace         name
    , relation          name
    , message           text )
language plpgsql
stable
as $body$
declare
    expected record;
    r record;
begin
    select relnamespace::regnamespace
         , relname
      into namespace
         , relation
      from pg_class
     where oid = relid;

    select c.conrelid
         , c.conkey
         , array_agg(a.attname) as "attnames"
         , array_agg(bitemporal.overlap_operator_for(a.attname)) as "conexclopnames"
      into expected
      from (select x.conrelid
                 , x.conkey
                 , unnest(x.conkey) as "attnum"
              from (select conrelid
                         , bitemporal.sort_array(conkey) as "conkey"
                      from pg_constraint
                     where conrelid = relid
                       and contype = 'p') x
             order by attnum asc) c
      join pg_attribute a on a.attrelid = c.conrelid and a.attnum = c.attnum
     group by c.conrelid, c.conkey;

    select y.conname
      into r
      from (select c.conname
                 , array_agg(c.attname) as "attnames"
                 , array_agg(c.oprname) as "conexclopnames"
              from (select x.oid
                         , x.conrelid
                         , x.conname
                         , array_agg(x.attnum) over (partition by x.oid) as "conkey"
                         , array_agg(x.opoid) over (partition by x.oid) as "conexclop"
                         , x.attnum
                         , a.attname
                         , x.opoid
                         , o.oprname
                      from (select oid
                                 , conrelid
                                 , conname
                                 , unnest(conkey) as "attnum"
                                 , unnest(conexclop) as "opoid"
                              from pg_constraint
                             where conrelid = relid
                               and contype = 'x'
                             order by oid asc, attnum asc) x
                      join pg_attribute a on a.attrelid = x.conrelid and a.attnum = x.attnum
                      join pg_operator o on o.oid = x.opoid) c
             where c.conkey = expected.conkey
             group by c.conname) y
     where y.attnames = expected.attnames
       and y.conexclopnames = expected.conexclopnames;

    if not found then
        message := format('Missing constraint. Expected a exclude constraint on %s with operators %s', expected.attnames, expected.conexclopnames);
        return next;
    end if;

    return;
end; $body$;

create or replace function bitemporal.validate_adjacency_constraint
    ( relid regclass )
returns table
    ( namespace         name
    , relation          name
    , message           text )
language plpgsql
stable
as $body$
declare
    expected record;
    r record;
begin
    select relnamespace::regnamespace
         , relname
      into namespace
         , relation
      from pg_class
     where oid = relid;

    select attrelid
         , array_agg(x.attnum) as "conkey"
         , array_agg(x.attname) as "attnames"
         , array_agg(x.conexclopname) as "conexclopnames"
      into expected
      from (select attrelid
                 , attnum
                 , attname
                 , bitemporal.adjacency_operator_for(attname) as "conexclopname"
              from pg_attribute
             where attrelid = relid
               and attnum > 0
               and attname not in (select system_time_name from bitemporal.params)
             order by attnum) x
     group by x.attrelid;

    select y.oid
      into r
      from (select x.oid
                 , array_agg(x.attnum) as "conkey"
                 , array_agg(x.attname) as "attnames"
                 , array_agg(x.oprname) as "conexclopnames"
              from (select c.oid
                         , c.attnum
                         , a.attname
                         , o.oprname
                      from (select oid
                                 , conrelid
                                 , unnest(conkey) as "attnum"
                                 , unnest(conexclop) as "opoid"
                              from pg_constraint
                             where conrelid = relid
                               and contype = 'x') c
                      join pg_operator o on o.oid = c.opoid
                      join pg_attribute a on a.attrelid = c.conrelid and a.attnum = c.attnum
                     order by c.oid, c.attnum) x
             group by x.oid) y
     where y.conkey = expected.conkey
       and y.attnames = expected.attnames
       and y.conexclopnames = expected.conexclopnames;

    if not found then
        message := format('Missing constraint. Expected a exclude constraint on %s with operators %s', expected.attnames, expected.conexclopnames);
        return next;
    end if;

    return;
end; $body$;

create or replace function bitemporal.history_relation_errors
    ( namespace         regnamespace
    , history_namespace regnamespace )
returns table
    ( namespace name
    , relation  name
    , message   text )
language sql
immutable
as $$
    with main as (select r.relnamespace
                       , r.relname
                       , a.attnum
                       , a.attname
                       , a.atttypid
                    from pg_catalog.pg_class as "r"
                    join pg_catalog.pg_attribute "a" on a.attrelid = r.oid
                   where r.relnamespace = namespace
                     and r.relkind = 'r'
                     and a.attnum > 0
                     and not a.attisdropped
                   order by r.relname, a.attnum)
       , hist_rel as (select r.relname
                        from pg_catalog.pg_class r
                       where r.relnamespace = history_namespace
                         and r.relkind = 'r'
                       order by r.relname)
       , hist_att as (select r.relname
                           , a.attnum
                           , a.attname
                           , a.atttypid
                        from pg_catalog.pg_class r
                        join pg_catalog.pg_attribute a on a.attrelid = r.oid
                       where r.relnamespace = history_namespace
                         and r.relkind = 'r'
                         and a.attnum > 0
                         and not a.attisdropped
                       order by r.relname, a.attnum)
    select history_namespace as "namespace"
         , x.mrelname as "relation"
         , case
             when x.is_missing_relation then 'Missing relation.'
             when x.is_missing_attribute then format('Missing attribute %s.', x.mattname)
             when x.is_type_mismatch then format('Attribute %s: Expected type %s, found %s.', x.mattname, x.matttypid, x.hatttypid)
             else 'Unknown'
           end as "message"
    from (select m.relname as "mrelname"
               , m.attname as "mattname"
               , m.atttypid::regtype as "matttypid"
               , h.relname as "hrelname"
               , ha.attname as "hattname"
               , ha.atttypid::regtype as "hatttypid"
               , h.relname is null "is_missing_relation"
               , ha.attname is null "is_missing_attribute"
               , ha.atttypid is null or m.atttypid <> ha.atttypid "is_type_mismatch"
            from main as "m"
       left join hist_rel as "h" using (relname)
       left join hist_att as "ha" using (relname, attname)
           order by m.relname, m.attnum) x
           where is_missing_relation
              or is_missing_attribute
              or is_type_mismatch;
$$;
