-- Run in Supabase SQL Editor. Replace admin UUID at the bottom.
create extension if not exists pgcrypto;
create table if not exists public.lottery_admins(user_id uuid primary key references auth.users(id) on delete cascade);
create table if not exists public.lottery_state(
 id integer primary key default 1 check(id=1),
 title text not null default '幸運抽籤', mode text not null default 'order' check(mode in ('order','group')),
 status text not null default 'closed' check(status in ('open','closed')),
 total integer not null default 20 check(total between 1 and 1000),
 remaining integer not null default 20 check(remaining between 0 and total),
 groups jsonb not null default '[]'::jsonb,
 round_id uuid not null default gen_random_uuid(),
 updated_at timestamptz not null default now()
);
create table if not exists public.lottery_tickets(
 id bigint generated always as identity primary key,
 round_id uuid not null,
 result text not null,
 drawn_by uuid,
 drawn_at timestamptz
);
create table if not exists public.lottery_draws(
 id bigint generated always as identity primary key,
 round_id uuid not null,
 participant_id uuid not null,
 result text not null,
 created_at timestamptz not null default now(),
 unique(round_id,participant_id),
 unique(round_id,result,id)
);
create index if not exists tickets_available on public.lottery_tickets(round_id) where drawn_by is null;
create index if not exists draws_round on public.lottery_draws(round_id);
alter table public.lottery_admins enable row level security;
alter table public.lottery_state enable row level security;
alter table public.lottery_tickets enable row level security;
alter table public.lottery_draws enable row level security;
revoke all on public.lottery_admins,public.lottery_state,public.lottery_tickets,public.lottery_draws from anon,authenticated;
grant select on public.lottery_state to anon,authenticated;
grant select on public.lottery_admins,public.lottery_draws to authenticated;
create policy "public state read" on public.lottery_state for select to anon,authenticated using(true);
create policy "admin membership read" on public.lottery_admins for select to authenticated using(user_id=(select auth.uid()));
create policy "admin draws read" on public.lottery_draws for select to authenticated using(exists(select 1 from public.lottery_admins where user_id=(select auth.uid())));
insert into public.lottery_state(id) values(1) on conflict(id) do nothing;

-- Public drawing: lock one state row to serialize simultaneous draws.
create or replace function public.draw_lottery(p_round uuid,p_participant uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare s public.lottery_state%rowtype; t public.lottery_tickets%rowtype; previous text;
begin
 if p_participant is null then raise exception 'Missing participant'; end if;
 select * into s from public.lottery_state where id=1 for update;
 if p_round<>s.round_id then raise exception 'This round has ended. Refresh the page.'; end if;
 select result into previous from public.lottery_draws where round_id=s.round_id and participant_id=p_participant;
 if found then return jsonb_build_object('result',previous,'already_drawn',true); end if;
 if s.status<>'open' then raise exception 'Drawing is not open'; end if;
 select * into t from public.lottery_tickets where round_id=s.round_id and drawn_by is null order by random() limit 1 for update;
 if not found then raise exception 'All tickets have been drawn'; end if;
 update public.lottery_tickets set drawn_by=p_participant,drawn_at=now() where id=t.id;
 insert into public.lottery_draws(round_id,participant_id,result) values(s.round_id,p_participant,t.result);
 update public.lottery_state set remaining=remaining-1,updated_at=now() where id=1;
 return jsonb_build_object('result',t.result,'already_drawn',false);
end $$;

create or replace function public.manage_lottery(
 p_action text,p_mode text default null,p_title text default null,p_total integer default null,p_groups jsonb default null
) returns void language plpgsql security definer set search_path='' as $$
declare s public.lottery_state%rowtype; g jsonb; label text; capacity integer; i integer; sum_capacity integer:=0; labels text[]:=array[]::text[];
begin
 if not exists(select 1 from public.lottery_admins where user_id=(select auth.uid())) then raise exception 'Not authorized'; end if;
 select * into s from public.lottery_state where id=1 for update;
 if p_action='close' then update public.lottery_state set status='closed',updated_at=now() where id=1;return;end if;
 if p_action='open' then update public.lottery_state set status='open',updated_at=now() where id=1;return;end if;
 if p_action not in ('save','reset') then raise exception 'Invalid action'; end if;
 if p_mode not in ('order','group') or p_total is null or p_total not between 1 and 1000 then raise exception 'Invalid mode or total'; end if;
 if p_title is null or length(p_title)>100 then raise exception 'Invalid title'; end if;
 if p_mode='group' then
   if jsonb_typeof(p_groups) is distinct from 'array' or jsonb_array_length(p_groups)=0 then raise exception 'Groups required'; end if;
   for g in select value from jsonb_array_elements(p_groups) loop
     label:=btrim(g->>'name');
     if label is null or length(label)=0 or length(label)>60 or label=any(labels) then raise exception 'Invalid or duplicate group name'; end if;
     if (g->>'count') is null or (g->>'count') !~ '^[0-9]{1,4}$' then raise exception 'Invalid group count'; end if;
     capacity:=(g->>'count')::integer;
     if capacity<1 then raise exception 'Group count must be positive'; end if;
     labels:=array_append(labels,label);sum_capacity:=sum_capacity+capacity;
   end loop;
   if sum_capacity<>p_total then raise exception 'Group totals mismatch'; end if;
 end if;
 if p_action='save' and s.total<>s.remaining then raise exception 'Already drawn: reset the round to change settings'; end if;
 if p_action='save' and s.status='open' then raise exception 'Close drawing before editing'; end if;
 -- New round for either save or reset; prevents old receipts from being reused.
 delete from public.lottery_draws;
 delete from public.lottery_tickets;
 update public.lottery_state set title=p_title,mode=p_mode,status='closed',total=p_total,remaining=p_total,
 groups=case when p_mode='group' then p_groups else '[]'::jsonb end,round_id=gen_random_uuid(),updated_at=now() where id=1;
 select * into s from public.lottery_state where id=1;
 if p_mode='order' then
   insert into public.lottery_tickets(round_id,result) select s.round_id,gs::text from generate_series(1,p_total) gs;
 else
   for g in select value from jsonb_array_elements(p_groups) loop
     insert into public.lottery_tickets(round_id,result)
       select s.round_id,g->>'name' from generate_series(1,(g->>'count')::integer);
   end loop;
 end if;
end $$;
revoke all on function public.draw_lottery(uuid,uuid) from public;
revoke all on function public.manage_lottery(text,text,text,integer,jsonb) from public;
grant execute on function public.draw_lottery(uuid,uuid) to anon,authenticated;
grant execute on function public.manage_lottery(text,text,text,integer,jsonb) to authenticated;
-- Enable realtime on lottery_state (run once; ignore 'already member' error if repeated).
alter publication supabase_realtime add table public.lottery_state;
-- IMPORTANT: after creating an admin in Authentication > Users, run separately:
-- insert into public.lottery_admins(user_id) values ('PASTE_ADMIN_AUTH_USER_UUID_HERE');
