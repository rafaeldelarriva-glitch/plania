-- Apply once after schema.sql, services.sql and refinements.sql on a fresh project.
-- These changes are already applied to the live PlanIA project.
begin;
alter table public.profiles add column if not exists trash_days integer not null default 30 check(trash_days in(0,7,30,60,90));
alter table public.profiles add column if not exists must_change_password boolean not null default false;
alter table public.events drop constraint events_category_id_fkey;
alter table public.events add constraint events_category_id_fkey foreign key(category_id) references public.categories on delete no action deferrable initially deferred;
alter table public.ticket_replies drop constraint ticket_replies_user_id_fkey;
alter table public.ticket_replies add constraint ticket_replies_user_id_fkey foreign key(user_id) references public.profiles on delete cascade;
alter table public.announcements alter column author_id drop not null;
alter table public.announcements drop constraint announcements_author_id_fkey;
alter table public.announcements add constraint announcements_author_id_fkey foreign key(author_id) references public.profiles on delete set null;
create or replace function private.active_user() returns boolean language sql stable security definer set search_path='' as $$select exists(select 1 from public.profiles p where p.id=auth.uid() and p.status='active' and not p.must_change_password) and exists(select 1 from auth.sessions s where s.id=(auth.jwt()->>'session_id')::uuid and s.user_id=auth.uid() and (s.not_after is null or s.not_after>now())) and (not exists(select 1 from auth.mfa_factors f where f.user_id=auth.uid() and f.status='verified') or (auth.jwt()->>'aal')='aal2')$$;
create or replace function private.is_admin() returns boolean language sql stable security definer set search_path='' as $$select exists(select 1 from public.profiles where id=auth.uid() and status='active' and role='admin') and private.active_user()$$;
revoke update on public.notifications from authenticated;
grant update(read_at) on public.notifications to authenticated;
create policy admin_announcement_receipts on public.notifications for select to authenticated using(announcement_id is not null and (select private.is_admin()));
create function public.announcement_receipts() returns table(announcement_id uuid,user_id uuid,full_name text,email text,read_at timestamptz) language sql stable security invoker set search_path='' as $$select n.announcement_id,n.user_id,p.full_name,p.email,n.read_at from public.notifications n join public.profiles p on p.id=n.user_id where n.announcement_id is not null and (select private.is_admin())$$;
revoke all on function public.announcement_receipts() from public;
grant execute on function public.announcement_receipts() to authenticated;
create extension if not exists pg_cron;
create extension if not exists pg_net with schema extensions;
create or replace function private.run_plania_worker() returns void language plpgsql security definer set search_path='' as $$begin perform private.process_notifications();perform net.http_post(url:='https://plmlusinojpnkqckqdxo.supabase.co/functions/v1/plania-service',headers:=jsonb_build_object('Content-Type','application/json','x-plania-worker',(select secret from private.worker_config)),body:='{}'::jsonb,timeout_milliseconds:=55000);end$$;
revoke all on function private.run_plania_worker() from public;
select cron.schedule('plania-notifications','* * * * *','select private.run_plania_worker()');
commit;
