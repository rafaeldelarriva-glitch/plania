-- PlanIA: independent project. No access to NOSOTROS.
begin;
create schema if not exists private;
revoke all on schema private from public;
grant usage on schema private to authenticated;
create table public.profiles(id uuid primary key references auth.users on delete cascade, email text not null, full_name text not null default '', phone text default '', company text default '', department text default '', position text default '', avatar_path text, timezone text not null default 'Europe/Madrid', region text default '', municipality text default '', start_view text not null default 'day', week_start integer not null default 1 check(week_start in(0,1)), day_start integer not null default 7 check(day_start between 0 and 23), day_end integer not null default 22 check(day_end between 1 and 24), role text not null default 'user' check(role in('user','admin')), status text not null default 'pending' check(status in('pending','active','blocked','rejected')), created_at timestamptz not null default now());
create table public.categories(id uuid primary key default gen_random_uuid(),user_id uuid not null references public.profiles on delete cascade,name text not null,group_name text not null default 'Trabajo',color text not null default '#648ce0',start_time time,end_time time,next_day boolean not null default false,leave_kind text check(leave_kind in('vacation','personal')),position integer not null default 0);
create table public.allowances(id uuid primary key default gen_random_uuid(),user_id uuid not null references public.profiles on delete cascade,year integer not null check(year between 2000 and 2200),vacation numeric not null default 30 check(vacation>=0),personal numeric not null default 6 check(personal>=0),unique(user_id,year));
create table public.holidays(id uuid primary key default gen_random_uuid(),user_id uuid not null references public.profiles on delete cascade,date date not null,name text not null,source_uid text,unique(user_id,date));
create table public.events(id uuid primary key default gen_random_uuid(),user_id uuid not null references public.profiles on delete cascade,category_id uuid references public.categories on delete restrict,title text not null check(length(title)>0),description text not null default '',starts_at timestamptz not null,ends_at timestamptz not null,all_day boolean not null default false,status text not null default 'planned' check(status in('planned','done','cancelled')),links jsonb not null default '[]',reminders integer[] not null default '{15}',external_uid text,series_id uuid,deleted_at timestamptz,created_at timestamptz not null default now(),updated_at timestamptz not null default now(),check(ends_at>starts_at));
create unique index events_import_identity on public.events(user_id,external_uid) where external_uid is not null;
create index events_user_date on public.events(user_id,starts_at,ends_at);
create table public.shortcuts(id uuid primary key default gen_random_uuid(),user_id uuid not null references public.profiles on delete cascade,name text not null,url text not null check(url ~ '^https?://'),icon_url text,position integer not null default 0);
create table public.attachments(id uuid primary key default gen_random_uuid(),user_id uuid not null references public.profiles on delete cascade,event_id uuid not null references public.events on delete cascade,name text not null,path text not null,mime text,size bigint,created_at timestamptz not null default now());
create table public.announcements(id uuid primary key default gen_random_uuid(),author_id uuid not null references public.profiles,title text not null,message text not null,priority text not null default 'normal' check(priority in('normal','important','maintenance')),starts_at timestamptz not null default now(),expires_at timestamptz,audience text not null default 'all' check(audience in('all','selected','admin','user','active','pending','blocked')),recipients uuid[] not null default '{}',created_at timestamptz not null default now());
create table public.notifications(id uuid primary key default gen_random_uuid(),user_id uuid not null references public.profiles on delete cascade,event_id uuid references public.events on delete cascade,announcement_id uuid references public.announcements on delete cascade,title text not null,message text not null default '',read_at timestamptz,created_at timestamptz not null default now());
create unique index notice_announcement_once on public.notifications(user_id,announcement_id) where announcement_id is not null;
create table public.tickets(id uuid primary key default gen_random_uuid(),user_id uuid not null references public.profiles on delete cascade,kind text not null default 'other',subject text not null,message text not null,status text not null default 'pending' check(status in('pending','reviewing','resolved')),created_at timestamptz not null default now());
create table public.ticket_replies(id uuid primary key default gen_random_uuid(),ticket_id uuid not null references public.tickets on delete cascade,user_id uuid not null references public.profiles,body text not null,created_at timestamptz not null default now());
create table public.audit_log(id bigint generated always as identity primary key,actor_id uuid references public.profiles on delete set null,target_id uuid,action text not null,details jsonb not null default '{}',created_at timestamptz not null default now());
create table public.delivery_log(id uuid primary key default gen_random_uuid(),user_id uuid not null references public.profiles on delete cascade,event_id uuid references public.events on delete cascade,kind text not null,channel text not null,status text not null,detail text,created_at timestamptz not null default now());
create table private.smtp_settings(user_id uuid primary key references public.profiles on delete cascade,encrypted_settings text not null,summary_enabled boolean not null default false,summary_hour integer not null default 7,updated_at timestamptz not null default now());
create or replace function private.active_user() returns boolean language sql stable security definer set search_path='' as $$select exists(select 1 from public.profiles where id=auth.uid() and status='active')$$;
create or replace function private.is_admin() returns boolean language sql stable security definer set search_path='' as $$select exists(select 1 from public.profiles where id=auth.uid() and status='active' and role='admin')$$;
revoke all on function private.active_user(),private.is_admin() from public;
grant execute on function private.active_user(),private.is_admin() to authenticated;
create or replace function private.initialize_user() returns trigger language plpgsql security definer set search_path='' as $$
begin
insert into public.profiles(id,email,full_name,role,status) values(new.id,new.email,coalesce(new.raw_user_meta_data->>'full_name',''),case when lower(new.email)='rafael.delarriva@gmail.com' then 'admin' else 'user' end,case when lower(new.email)='rafael.delarriva@gmail.com' then 'active' else 'pending' end);
insert into public.categories(user_id,name,group_name,color,start_time,end_time,next_day,leave_kind,position) values
(new.id,'Clases de universidad','Trabajo','#648ce0','09:00','10:30',false,null,1),
(new.id,'Guardia de tarde','Trabajo','#d89b42','15:00','20:00',false,null,2),
(new.id,'Guardia de noche','Trabajo','#9271c9','20:00','08:00',true,null,3),
(new.id,'Vacaciones','Trabajo','#55a77a',null,null,false,'vacation',4),
(new.id,'Asuntos propios','Trabajo','#42a8a5',null,null,false,'personal',5),
(new.id,'Comida','Trabajo','#cb8e68','14:00','15:00',false,null,6),
(new.id,'Baja','Ausencias justificadas','#d57872',null,null,false,null,7),
(new.id,'Enfermedad','Ausencias justificadas','#d57872',null,null,false,null,8),
(new.id,'Otros','Ausencias justificadas','#d57872',null,null,false,null,9),
(new.id,'Concierto','Personal','#cb7ca2',null,null,false,null,10),
(new.id,'Viaje','Personal','#cb7ca2',null,null,false,null,11),
(new.id,'Comida personal','Personal','#cb7ca2',null,null,false,null,12),
(new.id,'Cumpleaños','Personal','#cb7ca2',null,null,false,null,13),
(new.id,'Santo','Personal','#cb7ca2',null,null,false,null,14),
(new.id,'Peluquería','Personal','#cb7ca2',null,null,false,null,15),
(new.id,'Uñas','Personal','#cb7ca2',null,null,false,null,16),
(new.id,'Ocio','Personal','#cb7ca2',null,null,false,null,17);
insert into public.allowances(user_id,year) values(new.id,extract(year from now()));
return new;end $$;
revoke all on function private.initialize_user() from public;
create trigger initialize_user after insert on auth.users for each row execute function private.initialize_user();
-- Only verified owner identity is bootstrapped; access still requires a valid Auth session.
create or replace function private.protect_profile() returns trigger language plpgsql security definer set search_path='' as $$begin
if (new.role<>old.role or new.status<>old.status or new.email<>old.email or new.id<>old.id or new.must_change_password<>old.must_change_password) and not private.is_admin() and current_user<>'supabase_auth_admin' and auth.uid() is not null then raise exception 'Solo administración puede cambiar permisos';end if;
if old.role='admin' and old.status='active' and (new.role<>'admin' or new.status<>'active') then
perform pg_advisory_xact_lock(8173201);
if not exists(select 1 from public.profiles where id<>old.id and role='admin' and status='active') then raise exception 'Debe quedar un administrador activo';end if;end if;return new;end$$;
revoke all on function private.protect_profile() from public;
create trigger protect_profile before update on public.profiles for each row execute function private.protect_profile();
create or replace function private.audit_profile() returns trigger language plpgsql security definer set search_path='' as $$begin if new.role<>old.role or new.status<>old.status then insert into public.audit_log(actor_id,target_id,action,details) values(auth.uid(),new.id,'user.updated',jsonb_build_object('role',new.role,'status',new.status));end if;return new;end$$;
revoke all on function private.audit_profile() from public;
create trigger audit_profile after update on public.profiles for each row execute function private.audit_profile();
create or replace function private.check_event_owner() returns trigger language plpgsql security definer set search_path='' as $$begin
if new.category_id is not null and not exists(select 1 from public.categories where id=new.category_id and user_id=new.user_id) then raise exception 'Tipología inválida';end if;
new.updated_at=now();return new;end$$;
revoke all on function private.check_event_owner() from public;
create trigger check_event_owner before insert or update on public.events for each row execute function private.check_event_owner();
-- RLS is applied to every exposed table.
alter table public.profiles enable row level security;
create policy profile_read on public.profiles for select to authenticated using(id=(select auth.uid()) or (select private.is_admin()));
create policy profile_update on public.profiles for update to authenticated using((id=(select auth.uid()) and (select private.active_user())) or (select private.is_admin())) with check((id=(select auth.uid()) and (select private.active_user())) or (select private.is_admin()));
do $$declare t text;begin foreach t in array array['categories','allowances','holidays','events','shortcuts','attachments','notifications','tickets','delivery_log'] loop
execute format('alter table public.%I enable row level security',t);
execute format('create policy own_read on public.%I for select to authenticated using(user_id=(select auth.uid()) and (select private.active_user()))',t);
if t not in('delivery_log','notifications') then
execute format('create policy own_insert on public.%I for insert to authenticated with check(user_id=(select auth.uid()) and (select private.active_user()))',t);
execute format('create policy own_update on public.%I for update to authenticated using(user_id=(select auth.uid()) and (select private.active_user())) with check(user_id=(select auth.uid()) and (select private.active_user()))',t);
execute format('create policy own_delete on public.%I for delete to authenticated using(user_id=(select auth.uid()) and (select private.active_user()))',t);
end if;end loop;end$$;
create policy notice_read_update on public.notifications for update to authenticated using(user_id=(select auth.uid()) and (select private.active_user())) with check(user_id=(select auth.uid()) and (select private.active_user()));
create policy admin_tickets_read on public.tickets for select to authenticated using((select private.is_admin()));
create policy admin_tickets_update on public.tickets for update to authenticated using((select private.is_admin())) with check((select private.is_admin()));
alter table public.announcements enable row level security;
create policy announcements_read on public.announcements for select to authenticated using((select private.is_admin()) or ((select private.active_user()) and starts_at<=now() and (expires_at is null or expires_at>now()) and (audience='all' or (audience='selected' and (select auth.uid())=any(recipients)) or audience in(select role from public.profiles where id=(select auth.uid())) or audience in(select status from public.profiles where id=(select auth.uid())))));
create policy announcements_admin on public.announcements for all to authenticated using((select private.is_admin())) with check((select private.is_admin()) and author_id=(select auth.uid()));
alter table public.ticket_replies enable row level security;
create policy replies_read on public.ticket_replies for select to authenticated using((select private.is_admin()) or exists(select 1 from public.tickets where id=ticket_id and user_id=(select auth.uid())));
create policy replies_insert on public.ticket_replies for insert to authenticated with check(user_id=(select auth.uid()) and (select private.active_user()) and ((select private.is_admin()) or exists(select 1 from public.tickets where id=ticket_id and user_id=(select auth.uid()))));
alter table public.audit_log enable row level security;
create policy audit_admin_read on public.audit_log for select to authenticated using((select private.is_admin()));
create index tickets_owner on public.tickets(user_id);
create index attachments_event on public.attachments(event_id);
create index notifications_owner on public.notifications(user_id,created_at desc);
create index categories_owner on public.categories(user_id);
create index ticket_replies_ticket on public.ticket_replies(ticket_id);
grant select,insert,update,delete on all tables in schema public to authenticated;
revoke insert,update,delete on public.audit_log,public.delivery_log from authenticated;
revoke insert,delete on public.notifications from authenticated;
revoke all on all tables in schema public from anon;
grant select,insert,update,delete on all tables in schema private to service_role;
alter table private.smtp_settings enable row level security;
insert into storage.buckets(id,name,public,file_size_limit) values('plania','plania',false,20971520);
create policy file_owner_select on storage.objects for select to authenticated using(bucket_id='plania' and (storage.foldername(name))[1]=(select auth.uid())::text and (select private.active_user()));
create policy file_owner_insert on storage.objects for insert to authenticated with check(bucket_id='plania' and (storage.foldername(name))[1]=(select auth.uid())::text and (select private.active_user()));
create policy file_owner_update on storage.objects for update to authenticated using(bucket_id='plania' and (storage.foldername(name))[1]=(select auth.uid())::text and (select private.active_user())) with check(bucket_id='plania' and (storage.foldername(name))[1]=(select auth.uid())::text and (select private.active_user()));
create policy file_owner_delete on storage.objects for delete to authenticated using(bucket_id='plania' and (storage.foldername(name))[1]=(select auth.uid())::text and (select private.active_user()));
commit;
