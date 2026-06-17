-- AltiPin 临时组队：允许 anon 客户端使用 team:* 公共频道
-- 在 Supabase Dashboard → SQL Editor 中执行此脚本

alter table realtime.messages enable row level security;

drop policy if exists "altipin_anon_team_receive" on realtime.messages;
drop policy if exists "altipin_anon_team_send" on realtime.messages;

create policy "altipin_anon_team_receive"
on realtime.messages
for select
to anon
using (
  (select realtime.topic()) like 'team:%'
  and realtime.messages.extension in ('broadcast', 'presence')
);

create policy "altipin_anon_team_send"
on realtime.messages
for insert
to anon
with check (
  (select realtime.topic()) like 'team:%'
  and realtime.messages.extension in ('broadcast', 'presence')
);
