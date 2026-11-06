begin;
-- Explicit ownership checks for support files, including uploads in administrator replies.
create table public.support_attachments(id uuid primary key default gen_random_uuid(),user_id uuid not null references public.profiles on delete cascade,ticket_id uuid not null references public.tickets on delete cascade,name text not null,path text not null,mime text,size bigint,created_at timestamptz not null default now());
alter table public.support_attachments enable row level security;
create index support_attachments_ticket on public.support_attachments(ticket_id);
create policy support_file_read on public.support_attachments for select to authenticated using((select private.active_user()) and exists(select 1 from public.tickets t where t.id=ticket_id and (t.user_id=(select auth.uid()) or (select private.is_admin()))));
create policy support_file_insert on public.support_attachments for insert to authenticated with check(user_id=(select auth.uid()) and (select private.active_user()) and exists(select 1 from public.tickets t where t.id=ticket_id and (t.user_id=(select auth.uid()) or (select private.is_admin()))));
create policy support_file_update on public.support_attachments for update to authenticated using(user_id=(select auth.uid()) and (select private.active_user())) with check(user_id=(select auth.uid()) and (select private.active_user()) and exists(select 1 from public.tickets t where t.id=ticket_id and (t.user_id=(select auth.uid()) or (select private.is_admin()))));
create policy support_file_delete on public.support_attachments for delete to authenticated using(user_id=(select auth.uid()) and (select private.active_user()));
grant select,insert,update,delete on public.support_attachments to authenticated;
revoke all on public.support_attachments from anon;
create function private.validate_support_file() returns trigger language plpgsql security invoker set search_path='' as $$begin if split_part(new.path,'/',1)<>new.user_id::text or split_part(new.path,'/',2)<>'tickets' or split_part(new.path,'/',3)<>new.ticket_id::text then raise exception 'Ruta de adjunto inválida';end if;return new;end$$;
revoke all on function private.validate_support_file() from public;
create trigger support_file_validate before insert or update on public.support_attachments for each row execute function private.validate_support_file();
create policy support_file_download on storage.objects for select to authenticated using(bucket_id='plania' and (storage.foldername(name))[2]='tickets' and (select private.active_user()) and exists(select 1 from public.tickets t where t.id::text=(storage.foldername(name))[3] and (t.user_id=(select auth.uid()) or (select private.is_admin()))));
commit;
