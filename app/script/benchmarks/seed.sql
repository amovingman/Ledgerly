-- Fixture v1, seed 20261121. All application integrity indexes/constraints stay enabled.
CREATE TEMP TABLE fixture AS
WITH positions AS (
 SELECT i AS id,
 CASE WHEN i<=10000 THEN 1+(i-1)/1000 WHEN i<=28000 THEN 11+(i-10001)/200
      WHEN i<=38000 THEN 101+(i-28001)/25 ELSE 501+(i-38001)/24 END AS customer_id,
 CASE WHEN i<=10000 THEN 1+(i-1)/50 WHEN i<=28000 THEN 201+(i-10001)/50
      WHEN i<=38000 THEN 561+(i-28001)/25 ELSE 961+(i-38001)/24 END AS subscription_id,
 CASE WHEN i<=10000 THEN 1+((i-1)/50)%20 WHEN i<=28000 THEN 1+((i-10001)/50)%4 ELSE 1 END AS metric_index,
 CASE WHEN i<=10000 THEN (i-1)%50 WHEN i<=28000 THEN (i-10001)%50
      WHEN i<=38000 THEN 25+(i-28001)%25 ELSE 26+(i-38001)%24 END AS month_index
 FROM generate_series(1,50000) i
), amounts AS (
 SELECT *, (ARRAY['USD','CAD','EUR','GBP'])[1+(customer_id-1)%4] AS currency,
 4+3*metric_index AS unit_amount,
 30+((id*17+13+20261121)%997)+((id*17+26+20261121)%997)+((id*17+39+20261121)%997) AS quantity,
 timestamp '2022-09-01' + month_index*interval '1 month' AS period_start
 FROM positions
)
SELECT *, quantity::bigint*unit_amount AS amount, period_start+interval '1 month' AS period_end,
 'metric_'||metric_index AS metric FROM amounts;

INSERT INTO customers(id,name,email,stripe_customer_id,created_at,updated_at)
SELECT i,'Benchmark customer '||i,'customer-'||i||'@benchmark.example.test','cus_bench_'||i,
 timestamp '2022-09-01',timestamp '2022-09-01' FROM generate_series(1,1000) i;
INSERT INTO plans(id,name,metric,unit_amount,currency,billing_interval,created_at,updated_at)
SELECT c*20+m,'Benchmark metric '||m,'metric_'||m,4+3*m,(ARRAY['USD','CAD','EUR','GBP'])[c+1],
 'monthly',timestamp '2022-09-01',timestamp '2022-09-01' FROM generate_series(0,3) c CROSS JOIN generate_series(1,20) m;
INSERT INTO subscriptions(id,customer_id,plan_id,metric,unit_amount,currency,status,starts_at,created_at,updated_at)
SELECT DISTINCT subscription_id,customer_id,((customer_id-1)%4)*20+metric_index,metric,unit_amount,currency,
 'active',timestamp '2022-09-01',timestamp '2022-09-01',timestamp '2022-09-01' FROM fixture;
INSERT INTO invoices(id,customer_id,subscription_id,period_start,period_end,currency,amount,status,stripe_invoice_id,created_at,updated_at)
SELECT id,customer_id,subscription_id,period_start,period_end,currency,amount,
 CASE WHEN id%10=0 THEN 'issued' WHEN id%10=1 THEN 'payment_failed' WHEN id%20=3 THEN 'refunded' ELSE 'paid' END,
 'in_bench_'||id,period_end,period_end FROM fixture;
INSERT INTO invoice_line_items(id,invoice_id,metric,quantity,unit_amount,amount,created_at,updated_at)
SELECT id,id,metric,quantity,unit_amount,amount,period_end,period_end FROM fixture;
INSERT INTO usage_events(id,customer_id,subscription_id,invoice_line_item_id,metric,quantity,occurred_at,idempotency_key,request_fingerprint,created_at,updated_at)
SELECT (f.id-1)*3+p,f.customer_id,f.subscription_id,f.id,f.metric,
 ((f.id*17+p*13+20261121)%997)+10,
 f.period_start+(p*7)*interval '1 day','bench:'||f.id||':'||p,
 encode(sha256(convert_to(format('[%s,"%s",%s,"%s"]', f.subscription_id,f.metric,
 ((f.id*17+p*13+20261121)%997)+10,to_char(f.period_start+(p*7)*interval '1 day','YYYY-MM-DD"T"HH24:MI:SS.US"Z"')), 'UTF8')),'hex'),
 f.period_start+(p*7)*interval '1 day',f.period_start+(p*7)*interval '1 day'
 FROM fixture f CROSS JOIN generate_series(1,3) p;

INSERT INTO stripe_events(id,stripe_id,event_type,api_version,raw_payload,payload,status,attempts,processed_at,created_at,updated_at)
SELECT id,'evt_bench_seed_'||id,'invoice.paid','2026-11-18.endive',body::text,body,'processed',1,period_end,period_end,period_end
FROM (SELECT id,period_end,jsonb_build_object('id','evt_bench_seed_'||id,'object','event','type','invoice.paid',
 'api_version','2026-11-18.endive','livemode',false,'created',extract(epoch from period_end)::bigint,
 'data',jsonb_build_object('object',jsonb_build_object('id','in_bench_'||id,'object','invoice'))) AS body
 FROM fixture WHERE id%10>=2) s;
INSERT INTO ledger_transactions(id,invoice_id,journal_type,business_effect_key,currency,created_at,updated_at)
SELECT id,id,'issuance','invoice:'||id||':issuance',currency,period_end,period_end FROM fixture;
INSERT INTO ledger_transactions(id,invoice_id,journal_type,business_effect_key,currency,stripe_event_id,created_at,updated_at)
SELECT 50000+id,id,'payment','stripe:payment:ch_bench_'||id,currency,id,period_end,period_end FROM fixture WHERE id%10>=2;
INSERT INTO ledger_transactions(id,invoice_id,journal_type,business_effect_key,currency,stripe_event_id,created_at,updated_at)
SELECT 100000+id,id,'refund','stripe:refund:re_bench_'||id||'_0',currency,id,period_end,period_end FROM fixture WHERE id%20 IN (2,3);
INSERT INTO ledger_entries(ledger_transaction_id,account,debit,credit,created_at,updated_at)
SELECT id,'accounts_receivable',amount,0,period_end,period_end FROM fixture UNION ALL
SELECT id,'usage_revenue',0,amount,period_end,period_end FROM fixture UNION ALL
SELECT 50000+id,'stripe_clearing',amount,0,period_end,period_end FROM fixture WHERE id%10>=2 UNION ALL
SELECT 50000+id,'accounts_receivable',0,amount,period_end,period_end FROM fixture WHERE id%10>=2 UNION ALL
SELECT 100000+id,'sales_returns',CASE WHEN id%20=3 THEN amount ELSE amount/4 END,0,period_end,period_end FROM fixture WHERE id%20 IN (2,3) UNION ALL
SELECT 100000+id,'stripe_clearing',0,CASE WHEN id%20=3 THEN amount ELSE amount/4 END,period_end,period_end FROM fixture WHERE id%20 IN (2,3);
INSERT INTO stripe_payments(id,invoice_id,ledger_transaction_id,charge_id,payment_intent_id,invoice_payment_id,amount,currency,created_at,updated_at)
SELECT id,id,50000+id,'ch_bench_'||id,'pi_bench_'||id,'inpay_bench_'||id,amount,currency,period_end,period_end FROM fixture WHERE id%10>=2;
INSERT INTO stripe_refunds(id,stripe_payment_id,ledger_transaction_id,stripe_id,amount,currency,created_at,updated_at)
SELECT id,id,100000+id,'re_bench_'||id||'_0',CASE WHEN id%20=3 THEN amount ELSE amount/4 END,currency,period_end,period_end FROM fixture WHERE id%20 IN (2,3);
INSERT INTO outbox_records(stripe_event_id,attempts,available_at,dispatched_at,created_at,updated_at)
SELECT id,1,period_end,period_end,period_end,period_end FROM fixture WHERE id%10>=2;
