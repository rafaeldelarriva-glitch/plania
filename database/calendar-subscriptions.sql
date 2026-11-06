begin;
create table private.calendar_subscriptions (
 user_id uuid primary key references public.profiles(id) on delete cascade,
 token_hash text not null unique check(token_hash ~ '^[a-f0-9]{64}$'),
 category_ids uuid[] not null default '{}',
 enabled boolean not null default true,
 updated_at timestamptz not null default now()
);
alter table private.calendar_subscriptions enable row level security;
revoke all on private.calendar_subscriptions from public,anon,authenticated;
-- Service-only boundary: identity is verified by the Edge Function before management calls.
create function public.plania_calendar(op text, uid uuid default null, payload jsonb default '{}') returns jsonb
language plpgsql security definer set search_path='' as $$
declare s private.calendar_subscriptions; result jsonb; ids uuid[];
begin
 if op='feed' then
  select c.* into s from private.calendar_subscriptions c join public.profiles p on p.id=c.user_id
  where c.token_hash=payload->>'hash' and c.enabled and p.status='active' and not p.must_change_password;
  if not found then return null; end if;
  select jsonb_build_object('timezone',p.timezone,'events',coalesce((select jsonb_agg(jsonb_build_object(
   'id',e.id,'title',e.title,'description',e.description,'starts_at',e.starts_at,'ends_at',e.ends_at,
   'all_day',e.all_day,'created_at',e.created_at,'updated_at',e.updated_at,'category',c.name) order by e.starts_at,e.id)
   from public.events e left join public.categories c on c.id=e.category_id
   where e.user_id=s.user_id and e.deleted_at is null and e.status<>'cancelled'
   and (cardinality(s.category_ids)=0 or e.category_id=any(s.category_ids))),'[]'::jsonb)) into result
   from public.profiles p where p.id=s.user_id;
  return result;
 end if;
 if uid is null or not exists(select 1 from public.profiles p where p.id=uid and p.status='active' and not p.must_change_password) then raise exception 'Cuenta no activa'; end if;
 if op='status' then
  select jsonb_build_object('enabled',enabled,'category_ids',category_ids) into result from private.calendar_subscriptions where user_id=uid;
  return coalesce(result,'{"enabled":false,"category_ids":[]}'::jsonb);
 elsif op='revoke' then
  delete from private.calendar_subscriptions where user_id=uid;return '{"ok":true}';
 elsif op='create' then
  select coalesce(array_agg(value::uuid),'{}') into ids from jsonb_array_elements_text(coalesce(payload->'category_ids','[]'));
  if exists(select 1 from unnest(ids) i where not exists(select 1 from public.categories c where c.id=i and c.user_id=uid)) then raise exception 'Tipología no válida'; end if;
  insert into private.calendar_subscriptions(user_id,token_hash,category_ids) values(uid,payload->>'hash',ids)
  on conflict(user_id) do update set token_hash=excluded.token_hash,category_ids=excluded.category_ids,enabled=true,updated_at=now();
  return '{"ok":true}';
 end if;
 raise exception 'Acción no válida';
end $$;
revoke all on function public.plania_calendar(text,uuid,jsonb) from public,anon,authenticated;
grant execute on function public.plania_calendar(text,uuid,jsonb) to service_role;
commit;
