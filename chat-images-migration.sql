-- GameLink: add image sending to public and private chats.
-- Run this once in Supabase SQL Editor for the EXISTING project.

alter table public.public_messages add column if not exists image_url text;
alter table public.public_messages alter column content set default '';
alter table public.public_messages drop constraint if exists public_messages_content_check;
alter table public.public_messages add constraint public_messages_content_check check (char_length(content) between 0 and 1000);

alter table public.direct_messages add column if not exists image_url text;
alter table public.direct_messages alter column content set default '';
alter table public.direct_messages drop constraint if exists direct_messages_content_check;
alter table public.direct_messages add constraint direct_messages_content_check check (char_length(content) between 0 and 1000);

-- Images are stored in a public bucket: anyone who has an image URL can view it.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('chat-images', 'chat-images', true, 5242880, array['image/jpeg','image/png','image/gif','image/webp','image/avif'])
on conflict (id) do update set public=true, file_size_limit=5242880, allowed_mime_types=array['image/jpeg','image/png','image/gif','image/webp','image/avif'];

drop policy if exists "chat images public read" on storage.objects;
create policy "chat images public read" on storage.objects
for select using (bucket_id = 'chat-images');

drop policy if exists "members upload own chat images" on storage.objects;
create policy "members upload own chat images" on storage.objects
for insert to authenticated
with check (bucket_id = 'chat-images' and (storage.foldername(name))[1] = auth.uid()::text);

-- Allow only the primary site admin to remove another member from a trade room.
create or replace function public.kick_trade_room_member(target_room_id uuid, target_user_id uuid)
returns void language plpgsql security definer set search_path = public
as $$
begin
  if not public.is_admin() then raise exception 'Only the primary admin can remove trade room members'; end if;
  if target_user_id = auth.uid() then raise exception 'The room creator cannot remove themselves with this action'; end if;
  delete from public.trade_room_members
   where room_id = target_room_id and user_id = target_user_id;
  if not found then raise exception 'Member not found in this room'; end if;
end;
$$;
grant execute on function public.kick_trade_room_member(uuid, uuid) to authenticated;
