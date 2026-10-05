-- Kullanıcı silinince abonelikleri de silinsin (hesap silme bunu bekliyor)
-- Canlı tablo eski bir şemayla oluşturulduğu için subscriptions.user_id kısıtı
-- "on delete no action" kalmıştı; aboneliği olan kullanıcıda delete_own_account()
-- foreign key hatası veriyordu. Kısıtı cascade ile yeniden kuruyoruz.
alter table public.subscriptions
  drop constraint if exists subscriptions_user_id_fkey;

alter table public.subscriptions
  add constraint subscriptions_user_id_fkey
  foreign key (user_id) references auth.users(id) on delete cascade;
