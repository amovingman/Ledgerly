import {test} from 'node:test';
import assert from 'node:assert/strict';
import {amount, escape, integer, date, money} from '../app/public/dashboard-assets/format.mjs';
import {overview, collection, webhook} from '../app/public/dashboard-assets/views.mjs';

test('formats cents exactly above JavaScript integer precision and preserves negative credits', () => {
  assert.equal(amount('9007199254740993'),'90,071,992,547,409.93');
  assert.equal(amount('-64'),'−0.64');
  assert.equal(amount('0'),'0.00');
  assert.equal(integer('9007199254740993'),'9,007,199,254,740,993');
});
test('escapes untrusted content and uses explicit currencies and UTC dates', () => {
  assert.equal(escape('<img onerror="x">'), '&lt;img onerror=&quot;x&quot;&gt;');
  assert.match(money('64','CAD'), /CAD/);
  assert.equal(date('2026-01-01T00:30:00Z'),'Jan 1, 2026');
});
test('renders honest empty overview and never combines currencies', () => {
  const data={counts:{customers:0,usage:0,invoices:0,ledger:4,webhooks:0},ledger_totals:[{currency:'USD',debit:'64',credit:'64'},{currency:'CAD',debit:'85',credit:'85'}],recent_customers:[],recent_usage:[],recent_invoices:[],recent_webhooks:[]};
  const html=overview(data);
  assert.match(html,/No invoices yet/); assert.match(html,/USD/); assert.match(html,/CAD/);
  assert.doesNotMatch(html,/NaN|undefined/);
});
test('escapes server errors, names, search and webhook identifiers in rendered views', () => {
  const bad='<script>alert(1)</script>';
  const html=collection('customers',{data:[{id:'1',name:bad,email:bad,created_at:null}],meta:{total:1,page:1,per_page:25}},{q:bad});
  assert.doesNotMatch(html,/<script>/); assert.match(html,/&lt;script&gt;/);
  const detail=webhook({id:'1',stripe_id:bad,event_type:'invoice.paid',status:'review',attempts:0,last_error:bad},{data:[],meta:{total:0}});
  assert.doesNotMatch(detail,/<script>/);
});
test('preserves real signed entry differences and escapes compact overview records', () => {
  const bad='<script>alert(1)</script>';
  const html=overview({counts:{customers:0,usage:0,invoices:0,ledger:2,webhooks:0},
    ledger_totals:[{currency:'USD',debit:'50',credit:'50'}],
    recent_ledger:[{id:'1',invoice_id:'1',account:bad,created_at:'2026-11-22T18:28:34Z',currency:'USD',debit:'0',credit:'50'}],
    recent_customers:[],recent_usage:[],recent_invoices:[],recent_webhooks:[]});
  assert.match(html,/−0\.50/);
  assert.match(html,/2026-11-22 18:28:34/);
  assert.match(html,/data-label="Credits"/);
  assert.match(html,/&lt;script&gt;/);
  assert.doesNotMatch(html,/<script>|NaN|undefined/);
});
