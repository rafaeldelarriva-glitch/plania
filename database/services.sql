begin;
alter table public.notifications add column dedupe_key text;
create unique index notifications_dedupe on public.notifications(dedupe_key) where dedupe_key is not null;
alter table public.announcements add column send_email boolean not null default false;
alter table public.tickets alter column user_id drop not null;
alter table public.tickets add column guest_email text;
create table private.worker_config(id boolean primary key default true check(id),secret text not null);
insert into private.worker_config(secret) values(encode(extensions.gen_random_bytes(32),'hex'));
create table private.mail_queue(id uuid primary key default gen_random_uuid(),user_id uuid not null references public.profiles on delete cascade,event_id uuid references public.events on delete cascade,sender_id uuid references public.profiles on delete set null,subject text not null,body text not null,dedupe_key text unique not null,status text not null default 'pending',attempts integer not null default 0,claimed_at timestamptz,created_at timestamptz not null default now());
create table private.rate_limit(key text primary key,window_start timestamptz not null default now(),count integer not null default 1);
alter table private.mail_queue enable row level security;
alter table private.worker_config enable row level security;
alter table private.rate_limit enable row level security;
create or replace function public.plania_service(op text,uid uuid default null,payload jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$declare result jsonb; allowed boolean;begin
if coalesce(auth.jwt()->>'role','')<>'service_role' then raise exception 'Not authorized';end if;
if op='session-check' then select jsonb_build_object('valid',exists(select 1 from auth.sessions s where s.id=(payload->>'session_id')::uuid and s.user_id=uid and (s.not_after is null or s.not_after>now()))) into result;return result;
elsif op='sessions-revoke' then delete from auth.sessions where user_id=uid;return '{"ok":true}';
elsif op='crypto-key' then select jsonb_build_object('secret',secret) into result from private.worker_config;return result;
elsif op='smtp-get' then select to_jsonb(s) into result from private.smtp_settings s where user_id=uid;return result;
elsif op='smtp-save' then insert into private.smtp_settings(user_id,encrypted_settings,summary_enabled,summary_hour) values(uid,payload->>'encrypted_settings',coalesce((payload->>'summary_enabled')::boolean,false),coalesce((payload->>'summary_hour')::integer,7)) on conflict(user_id) do update set encrypted_settings=excluded.encrypted_settings,summary_enabled=excluded.summary_enabled,summary_hour=excluded.summary_hour,updated_at=now();return '{"ok":true}';
elsif op='worker-check' then select secret=payload->>'secret' into allowed from private.worker_config;return jsonb_build_object('allowed',coalesce(allowed,false));
elsif op='queue-take' then with q as(select id from private.mail_queue where (status='pending' or (status='sending' and claimed_at<now()-interval '5 minutes')) and attempts<3 order by created_at limit 15 for update skip locked), upd as(update private.mail_queue m set status='sending',attempts=attempts+1,claimed_at=now() from q where m.id=q.id returning m.*) select coalesce(jsonb_agg(to_jsonb(upd)),'[]') into result from upd;return result;
elsif op='queue-result' then update private.mail_queue set status=case when (payload->>'ok')::boolean then 'sent' when attempts>=3 then 'failed' else 'pending' end where id=(payload->>'id')::uuid;return '{"ok":true}';
elsif op='guest-allowed' then insert into private.rate_limit(key) values(payload->>'key') on conflict(key) do update set count=case when private.rate_limit.window_start<now()-interval '1 hour' then 1 else private.rate_limit.count+1 end,window_start=case when private.rate_limit.window_start<now()-interval '1 hour' then now() else private.rate_limit.window_start end returning count<=5 into allowed;return jsonb_build_object('allowed',allowed);
end if;raise exception 'Unknown operation';end $$;
revoke all on function public.plania_service(text,uuid,jsonb) from public,anon,authenticated;
grant execute on function public.plania_service(text,uuid,jsonb) to service_role;
create or replace function private.delete_protection() returns trigger language plpgsql security definer set search_path='' as $$begin if old.role='admin' and old.status='active' then perform pg_advisory_xact_lock(8173201);if not exists(select 1 from public.profiles where id<>old.id and role='admin' and status='active') then raise exception 'No se puede eliminar el último administrador activo';end if;end if;return old;end$$;
revoke all on function private.delete_protection() from public;
create trigger protect_profile_delete before delete on public.profiles for each row execute function private.delete_protection();
create or replace function private.revoke_blocked_sessions() returns trigger language plpgsql security definer set search_path='' as $$begin if new.status<>'active' then delete from auth.sessions where user_id=new.id;end if;return new;end$$;
revoke all on function private.revoke_blocked_sessions() from public;
create trigger revoke_blocked_sessions after update of status on public.profiles for each row execute function private.revoke_blocked_sessions();
create or replace function private.validate_attachment() returns trigger language plpgsql security definer set search_path='' as $$begin if not exists(select 1 from public.events where id=new.event_id and user_id=new.user_id) or split_part(new.path,'/',1)<>new.user_id::text then raise exception 'Evento o ruta inválidos';end if;return new;end$$;
revoke all on function private.validate_attachment() from public;
create trigger attachment_validate before insert or update on public.attachments for each row execute function private.validate_attachment();
create or replace function private.process_notifications() returns void language plpgsql security definer set search_path='' as $$begin
insert into public.notifications(user_id,event_id,title,message,dedupe_key)
select e.user_id,e.id,e.title,'Tu evento empieza el '||to_char(e.starts_at at time zone p.timezone,'DD/MM/YYYY HH24:MI'),'event:'||e.id||':'||e.starts_at||':'||r.m
from public.events e join public.profiles p on p.id=e.user_id cross join lateral unnest(e.reminders) r(m)
where p.status='active' and e.status<>'cancelled' and e.deleted_at is null and e.starts_at-r.m*interval '1 minute'<=now() and e.starts_at-r.m*interval '1 minute'>now()-interval '2 minutes'
on conflict(dedupe_key) where dedupe_key is not null do nothing;
insert into public.notifications(user_id,announcement_id,title,message)
select p.id,a.id,a.title,a.message from public.announcements a join public.profiles p on p.status='active'
where a.starts_at<=now() and (a.expires_at is null or a.expires_at>now()) and (a.audience='all' or (a.audience='selected' and p.id=any(a.recipients)) or a.audience=p.role or a.audience=p.status)
on conflict(user_id,announcement_id) where announcement_id is not null do nothing;
insert into private.mail_queue(user_id,event_id,subject,body,dedupe_key,sender_id)
select n.user_id,n.event_id,n.title,n.message,'notice:'||n.id,coalesce(a.author_id,n.user_id) from public.notifications n left join public.announcements a on a.id=n.announcement_id join private.smtp_settings s on s.user_id=coalesce(a.author_id,n.user_id)
where n.created_at>now()-interval '10 minutes' and (n.event_id is not null or a.send_email) on conflict(dedupe_key) do nothing;
insert into private.mail_queue(user_id,subject,body,dedupe_key)
select p.id,'Tu agenda de hoy · PlanIA',coalesce((select string_agg(to_char(e.starts_at at time zone p.timezone,'HH24:MI')||' · '||e.title,E'\n' order by e.starts_at) from public.events e where e.user_id=p.id and e.deleted_at is null and e.status<>'cancelled' and e.starts_at<(date_trunc('day',now() at time zone p.timezone)+interval '1 day') at time zone p.timezone and e.ends_at>date_trunc('day',now() at time zone p.timezone) at time zone p.timezone),'Hoy no tienes eventos. Disfruta de tu día.'),'summary:'||p.id||':'||(now() at time zone p.timezone)::date
from public.profiles p join private.smtp_settings s on s.user_id=p.id where p.status='active' and s.summary_enabled and extract(hour from now() at time zone p.timezone)=s.summary_hour on conflict(dedupe_key) do nothing;
-- Automatically remove read-only support rate-limit counters after seven days.
delete from private.rate_limit where window_start<now()-interval '7 days';
end$$;
revoke all on function private.process_notifications() from public;
create or replace function private.ticket_notice() returns trigger language plpgsql security definer set search_path='' as $$declare owner uuid;begin
if tg_table_name='tickets' then insert into public.notifications(user_id,title,message) select id,'Nueva consulta #'||left(new.id::text,8),new.subject from public.profiles where role='admin' and status='active';else
select user_id into owner from public.tickets where id=new.ticket_id;
if owner is distinct from new.user_id and owner is not null then insert into public.notifications(user_id,title,message) values(owner,'Respuesta a tu consulta',new.body);else insert into public.notifications(user_id,title,message) select id,'Nueva respuesta a una consulta',new.body from public.profiles where role='admin' and status='active' and id<>new.user_id;end if;end if;return new;end$$;
revoke all on function private.ticket_notice() from public;
create trigger ticket_notice after insert on public.tickets for each row execute function private.ticket_notice();
create trigger ticket_reply_notice after insert on public.ticket_replies for each row execute function private.ticket_notice();
commit;
