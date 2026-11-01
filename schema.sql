-- S&HA Cloud POS v2. Run in a NEW Supabase project's SQL Editor.
create extension if not exists pgcrypto;
create table public.profiles (id uuid primary key references auth.users(id) on delete cascade, email text, display_name text, role text not null default 'employee' check(role in ('owner','manager','employee')), active boolean not null default true, created_at timestamptz default now());
create table public.locations (id uuid primary key default gen_random_uuid(), name text not null unique, kind text not null check(kind in ('warehouse','van')), assigned_user uuid references public.profiles(id), created_at timestamptz default now());
create table public.customers (id uuid primary key default gen_random_uuid(), legacy_id text unique, name text not null, store text default '', phone text default '', address text default '', notes text default '', opening numeric(12,2) not null default 0, created_at timestamptz default now());
create table public.products (id uuid primary key default gen_random_uuid(), legacy_id text unique, name text not null, sku text default '', price numeric(12,2) not null default 0 check(price>=0), cost numeric(12,2) not null default 0 check(cost>=0), promo boolean not null default true);
alter table public.products add column if not exists retail_price numeric(12,2) not null default 0 check(retail_price>=0);
create table public.stock (location_id uuid references public.locations on delete restrict, product_id uuid references public.products on delete restrict, quantity integer not null default 0 check(quantity>=0), primary key(location_id,product_id));
create table public.invoices (id uuid primary key default gen_random_uuid(), legacy_id text unique, number text not null unique, customer_id uuid not null references public.customers, location_id uuid not null references public.locations, created_by uuid references public.profiles, created_at timestamptz not null default now(), subtotal numeric(12,2) not null, discount numeric(12,2) not null default 0, total numeric(12,2) not null, notes text default '');
alter table public.invoices add column if not exists sale_type text not null default 'wholesale' check(sale_type in ('retail','wholesale'));
create table public.invoice_lines (id uuid primary key default gen_random_uuid(), invoice_id uuid not null references public.invoices on delete cascade, product_id uuid references public.products, name text not null, qty integer not null check(qty>0), free integer not null default 0 check(free>=0), price numeric(12,2) not null, cost numeric(12,2) not null default 0);
create table public.payments (id uuid primary key default gen_random_uuid(), legacy_id text unique, customer_id uuid not null references public.customers, invoice_id uuid references public.invoices, amount numeric(12,2) not null check(amount>0), note text default '', created_by uuid references public.profiles, created_at timestamptz not null default now());
create table public.stock_movements (id uuid primary key default gen_random_uuid(), product_id uuid not null references public.products, from_location uuid references public.locations, to_location uuid references public.locations, quantity integer not null check(quantity>0), reason text not null, actor uuid references public.profiles, created_at timestamptz default now());
create sequence public.invoice_seq start 1;
create function public.on_signup() returns trigger language plpgsql security definer set search_path='' as $$begin insert into public.profiles(id,email,display_name) values(new.id,new.email,coalesce(new.raw_user_meta_data->>'name',new.email));return new;end$$;
create trigger create_profile after insert on auth.users for each row execute function public.on_signup();
create function public.my_role() returns text language sql stable security definer set search_path='' as $$select role from public.profiles where id=(select auth.uid()) and active=true$$;
create function public.can_use_location(loc uuid) returns boolean language sql stable security definer set search_path='' as $$select public.my_role() in ('owner','manager') or exists(select 1 from public.locations where id=loc and assigned_user=(select auth.uid()))$$;
create function public.is_staff() returns boolean language sql stable security definer set search_path='' as $$select public.my_role() is not null$$;
alter table public.profiles enable row level security;
alter table public.locations enable row level security;
alter table public.customers enable row level security;
alter table public.products enable row level security;
alter table public.stock enable row level security;
alter table public.invoices enable row level security;
alter table public.invoice_lines enable row level security;
alter table public.payments enable row level security;
alter table public.stock_movements enable row level security;
create policy profile_read on public.profiles for select to authenticated using(id=(select auth.uid()) or public.my_role() in ('owner','manager'));
create policy locations_read on public.locations for select to authenticated using(public.can_use_location(id));
create policy customers_read on public.customers for select to authenticated using(public.is_staff());
create policy customers_write on public.customers for all to authenticated using(public.my_role() in ('owner','manager')) with check(public.my_role() in ('owner','manager'));
create policy products_read on public.products for select to authenticated using(public.is_staff());
create policy products_write on public.products for all to authenticated using(public.my_role() in ('owner','manager')) with check(public.my_role() in ('owner','manager'));
create policy stock_read on public.stock for select to authenticated using(public.can_use_location(location_id));
create policy invoices_read on public.invoices for select to authenticated using(public.can_use_location(location_id));
create policy lines_read on public.invoice_lines for select to authenticated using(exists(select 1 from public.invoices i where i.id=invoice_id and public.can_use_location(i.location_id)));
create policy payments_read on public.payments for select to authenticated using(public.my_role() in ('owner','manager') or created_by=(select auth.uid()));
create policy movements_read on public.stock_movements for select to authenticated using(public.my_role() in ('owner','manager') or public.can_use_location(from_location) or public.can_use_location(to_location));
-- Hide costs and global balances from employees via dedicated SECURITY INVOKER views, not direct product table reads.
-- Product cost is restricted to owners/managers via RLS-protected cost view.
-- Employees can see base product fields only.
revoke select on public.products from authenticated;
grant select(id,legacy_id,name,sku,price,retail_price,promo) on public.products to authenticated;
revoke select on public.customers from authenticated;
grant select(id,legacy_id,name,store,phone,address) on public.customers to authenticated;
-- Restricted fields are retrieved through owner-only RPCs, not direct table SELECT.
revoke select on public.invoice_lines from authenticated;
grant select(id,invoice_id,product_id,name,qty,free,price) on public.invoice_lines to authenticated;
create function public.owner_invoice_lines() returns setof public.invoice_lines language plpgsql security definer set search_path='' as $$begin if public.my_role() not in ('owner','manager') then raise exception 'Not authorized';end if;return query select * from public.invoice_lines;end$$;
revoke all on function public.owner_invoice_lines() from public,anon;
grant execute on function public.owner_invoice_lines() to authenticated;
create function public.owner_products() returns setof public.products language plpgsql security definer set search_path='' as $$begin if public.my_role() not in ('owner','manager') then raise exception 'Not authorized';end if;return query select * from public.products;end$$;
create function public.owner_customers() returns setof public.customers language plpgsql security definer set search_path='' as $$begin if public.my_role() not in ('owner','manager') then raise exception 'Not authorized';end if;return query select * from public.customers;end$$;
revoke all on function public.owner_products(),public.owner_customers() from public,anon;
grant execute on function public.owner_products(),public.owner_customers() to authenticated;
create function public.create_invoice(p_customer uuid,p_location uuid,p_lines jsonb,p_discount numeric default 0,p_paid numeric default 0,p_notes text default '') returns text language plpgsql security definer set search_path='' as $$
declare v_number text;v_id uuid;v_sub numeric:=0;v_total numeric;v_line jsonb;v_pid uuid;v_qty integer;v_free integer;v_price numeric;v_cost numeric;v_name text;v_promo boolean;v_available integer;v_needed integer;v_check record;
begin
 if not public.can_use_location(p_location) then raise exception 'Not authorized for location';end if;
 if not exists(select 1 from public.customers where id=p_customer) then raise exception 'Customer not found';end if;
 if jsonb_typeof(p_lines)<>'array' or jsonb_array_length(p_lines)=0 or jsonb_array_length(p_lines)>100 then raise exception 'Invalid lines';end if;
 -- Lock the entire location's stock in stable product order to prevent overselling.
 for v_check in select s.product_id from public.stock s where s.location_id=p_location order by s.product_id for update loop null;end loop;
 for v_line in select value from jsonb_array_elements(p_lines) loop
  v_pid=(v_line->>'product_id')::uuid;v_qty=(v_line->>'qty')::integer;v_price=(v_line->>'price')::numeric;
  if v_qty is null or v_qty<1 or v_qty>100000 or v_price is null or v_price<0 or v_price>1000000 then raise exception 'Invalid line';end if;
  select name,cost,promo into strict v_name,v_cost,v_promo from public.products where id=v_pid;
  v_free=case when p_notes like '[RETAIL]%' then 0 when v_promo then v_qty/12 else 0 end;
  v_needed=v_qty+v_free;
  select quantity into v_available from public.stock where location_id=p_location and product_id=v_pid;
  if coalesce(v_available,0)<v_needed then raise exception 'Insufficient stock: %',v_name;end if;
  update public.stock set quantity=quantity-v_needed where location_id=p_location and product_id=v_pid;
  v_sub=v_sub+round(v_qty*v_price,2);
 end loop;
 if p_discount<0 or p_discount>v_sub then raise exception 'Invalid discount';end if;
 v_total=round(v_sub-p_discount,2);
 if p_paid<0 or p_paid>v_total then raise exception 'Invalid payment';end if;
 v_number='SHA-'||lpad(nextval('public.invoice_seq')::text,5,'0');
 insert into public.invoices(number,customer_id,location_id,created_by,subtotal,discount,total,notes,sale_type) values(v_number,p_customer,p_location,auth.uid(),v_sub,p_discount,v_total,p_notes,case when p_notes like '[RETAIL]%' then 'retail' else 'wholesale' end) returning id into v_id;
 for v_line in select value from jsonb_array_elements(p_lines) loop
  v_pid=(v_line->>'product_id')::uuid;v_qty=(v_line->>'qty')::integer;v_price=(v_line->>'price')::numeric;
  select name,cost,promo into strict v_name,v_cost,v_promo from public.products where id=v_pid;
  v_free=case when p_notes like '[RETAIL]%' then 0 when v_promo then v_qty/12 else 0 end;
  insert into public.invoice_lines(invoice_id,product_id,name,qty,free,price,cost) values(v_id,v_pid,v_name,v_qty,v_free,v_price,v_cost);
  insert into public.stock_movements(product_id,from_location,quantity,reason,actor) values(v_pid,p_location,v_qty+v_free,'Invoice '||v_number,auth.uid());
 end loop;
 if p_paid>0 then insert into public.payments(customer_id,invoice_id,amount,note,created_by) values(p_customer,v_id,p_paid,'Payment on '||v_number,auth.uid());end if;
 return v_number;
end$$;
create function public.transfer_stock(p_product uuid,p_from uuid,p_to uuid,p_qty integer) returns void language plpgsql security definer set search_path='' as $$
declare v_stock integer;v_rec record;
begin
 if public.my_role() not in ('owner','manager') then raise exception 'Only managers can transfer';end if;
 if p_from=p_to or p_qty is null or p_qty<=0 then raise exception 'Invalid transfer';end if;
 for v_rec in select location_id from public.stock where product_id=p_product and location_id in (p_from,p_to) order by location_id for update loop null;end loop;
 select quantity into v_stock from public.stock where location_id=p_from and product_id=p_product;
 if coalesce(v_stock,0)<p_qty then raise exception 'Insufficient source stock';end if;
 update public.stock set quantity=quantity-p_qty where location_id=p_from and product_id=p_product;
 insert into public.stock(location_id,product_id,quantity) values(p_to,p_product,p_qty) on conflict(location_id,product_id) do update set quantity=public.stock.quantity+excluded.quantity;
 insert into public.stock_movements(product_id,from_location,to_location,quantity,reason,actor) values(p_product,p_from,p_to,p_qty,'Transfer',auth.uid());
end$$;
create function public.adjust_stock(p_product uuid,p_location uuid,p_qty integer) returns void language plpgsql security definer set search_path='' as $$
begin
 if public.my_role() not in ('owner','manager') then raise exception 'Not authorized';end if;
 if p_qty is null or p_qty=0 then raise exception 'Invalid adjustment';end if;
 insert into public.stock(location_id,product_id,quantity) values(p_location,p_product,greatest(p_qty,0)) on conflict(location_id,product_id) do update set quantity=public.stock.quantity+p_qty;
 if p_qty<0 and not found then raise exception 'Insufficient stock';end if;
 insert into public.stock_movements(product_id,to_location,quantity,reason,actor) values(p_product,p_location,abs(p_qty),'Adjustment '||p_qty,auth.uid());
end$$;
create function public.record_payment(p_customer uuid,p_amount numeric,p_note text default '') returns void language plpgsql security definer set search_path='' as $$begin
 if public.my_role() not in ('owner','manager') then raise exception 'Not authorized';end if;
 if p_amount<=0 then raise exception 'Invalid amount';end if;
 insert into public.payments(customer_id,amount,note,created_by) values(p_customer,p_amount,p_note,auth.uid());
end$$;
-- Owner-only legacy import. Repeat imports are rejected by legacy_id uniqueness.
create function public.import_legacy(p_data jsonb,p_warehouse uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare x jsonb;c jsonb;v_c uuid;v_p uuid;v_i uuid;v_line jsonb;v_old text;v_count int:=0;v_num text;
begin
 if public.my_role()<>'owner' then raise exception 'Owner only';end if;
 if not exists(select 1 from public.locations where id=p_warehouse and kind='warehouse') then raise exception 'Select warehouse';end if;
 if jsonb_typeof(p_data->'customers')<>'array' or jsonb_typeof(p_data->'products')<>'array' or jsonb_typeof(p_data->'invoices')<>'array' or jsonb_typeof(p_data->'payments')<>'array' then raise exception 'Invalid legacy backup';end if;
 for x in select value from jsonb_array_elements(p_data->'customers') loop
  insert into public.customers(legacy_id,name,store,phone,address,notes,opening) values(x->>'id',x->>'name',coalesce(x->>'store',''),coalesce(x->>'phone',''),coalesce(x->>'address',''),coalesce(x->>'notes',''),coalesce((x->>'opening')::numeric,0)) on conflict(legacy_id) do nothing;
 end loop;
 for x in select value from jsonb_array_elements(p_data->'products') loop
  insert into public.products(legacy_id,name,sku,price,cost,promo) values(x->>'id',x->>'name',coalesce(x->>'sku',''),coalesce((x->>'price')::numeric,0),coalesce((x->>'cost')::numeric,0),coalesce((x->>'promo')::boolean,true)) on conflict(legacy_id) do nothing;
  select id into v_p from public.products where legacy_id=x->>'id';
  insert into public.stock(location_id,product_id,quantity) values(p_warehouse,v_p,coalesce((x->>'stock')::integer,0)) on conflict do nothing;
 end loop;
 for x in select value from jsonb_array_elements(p_data->'invoices') loop
  select id into v_c from public.customers where legacy_id=x->>'customerId';
  v_num=x->>'number';
  if v_c is null then raise exception 'Missing invoice customer';end if;
  insert into public.invoices(legacy_id,number,customer_id,location_id,created_by,created_at,subtotal,discount,total,notes) values(x->>'id','LEGACY-'||v_num,v_c,p_warehouse,auth.uid(),coalesce((x->>'date')::timestamptz,now()),coalesce((x->>'subtotal')::numeric,0),coalesce((x->>'discount')::numeric,0),coalesce((x->>'total')::numeric,0),coalesce(x->>'notes','')) on conflict(legacy_id) do nothing returning id into v_i;
  if v_i is not null then
   for v_line in select value from jsonb_array_elements(x->'lines') loop
    select id into v_p from public.products where legacy_id=v_line->>'productId';
    insert into public.invoice_lines(invoice_id,product_id,name,qty,free,price,cost) values(v_i,v_p,coalesce(v_line->>'name','Legacy item'),(v_line->>'qty')::integer,coalesce((v_line->>'free')::integer,0),coalesce((v_line->>'price')::numeric,0),coalesce((v_line->>'cost')::numeric,0));
   end loop;
   v_count=v_count+1;
  end if;
 end loop;
 for x in select value from jsonb_array_elements(p_data->'payments') loop
  select id into v_c from public.customers where legacy_id=x->>'customerId';
  insert into public.payments(legacy_id,customer_id,amount,note,created_by,created_at) values(x->>'id',v_c,(x->>'amount')::numeric,coalesce(x->>'note',''),auth.uid(),coalesce((x->>'date')::timestamptz,now())) on conflict(legacy_id) do nothing;
 end loop;
 return jsonb_build_object('new_invoices',v_count);
end$$;
-- Deny client direct writes to financial/stock tables; use audited transactional RPCs.
revoke insert,update,delete on public.stock,public.invoices,public.invoice_lines,public.payments,public.stock_movements,public.locations,public.profiles from authenticated;
revoke all on function public.import_legacy(jsonb,uuid) from public,anon;
revoke all on function public.create_invoice(uuid,uuid,jsonb,numeric,numeric,text) from public,anon;
revoke all on function public.transfer_stock(uuid,uuid,uuid,integer) from public,anon;
revoke all on function public.adjust_stock(uuid,uuid,integer) from public,anon;
revoke all on function public.record_payment(uuid,numeric,text) from public,anon;
grant execute on function public.import_legacy(jsonb,uuid),public.create_invoice(uuid,uuid,jsonb,numeric,numeric,text),public.transfer_stock(uuid,uuid,uuid,integer),public.adjust_stock(uuid,uuid,integer),public.record_payment(uuid,numeric,text) to authenticated;
insert into public.locations(name,kind) values('Main Warehouse','warehouse');
-- AFTER first account signs up, manually promote it using SQL Editor:
-- update public.profiles set role='owner' where email='YOUR_EMAIL_HERE';
-- Employee accounts: invite via Supabase Auth Users dashboard; assign van:
-- insert into public.locations(name,kind,assigned_user) select 'Van 1','van',id from public.profiles where email='EMPLOYEE_EMAIL_HERE';
