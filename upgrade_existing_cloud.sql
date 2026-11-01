-- Run only if you ALREADY ran the original S&HA cloud schema.
-- Back up your Supabase database first. Do not rerun schema.sql on an existing project.
alter table public.products add column if not exists retail_price numeric(12,2) not null default 0 check(retail_price>=0);
alter table public.invoices add column if not exists sale_type text not null default 'wholesale' check(sale_type in ('retail','wholesale'));
grant select(retail_price) on public.products to authenticated;
create or replace function public.create_invoice(p_customer uuid,p_location uuid,p_lines jsonb,p_discount numeric default 0,p_paid numeric default 0,p_notes text default '') returns text language plpgsql security definer set search_path='' as $$
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
