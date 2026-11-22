import {escape as e, integer, amount, title, code, status, invoiceLink, customerLink} from './format.mjs?v=1';

const labels = {customers:'Customers', usage:'Usage events', invoices:'Invoices', webhooks:'Webhooks', ledger:'Ledger entries'};
const stamp = value => value ? e(new Date(value).toISOString().slice(0,19).replace('T',' ')) : '—';
const td = (label, value, cls='') => `<td data-label="${e(label)}" class="${cls}">${value}</td>`;
const named = v => `<a class="record-link clipped" title="${e(v.name)}" href="#customers/${e(v.id)}">${e(v.name)}</a>`;
const noRows = label => `<div class="empty-state"><strong>No ${e(label)} yet</strong><p>Records appear here after they are received by the API.</p></div>`;
const seeAll = section => `<a class="text-link" href="#${section}">View all</a>`;
const panel = (label, section, note, content) => `<section class="panel overview-panel"><header class="panel-header"><div><h2>${e(label)}</h2><p>${e(note)}</p></div>${seeAll(section)}</header>${content}</section>`;
function table(label, heads, rows) {
  return rows.length ? `<div class="overview-table-wrap"><table class="overview-table"><caption class="sr-only">${e(label)}</caption><thead><tr>${heads.map(h=>`<th scope="col" class="${['Amount','Quantity'].includes(h) ? 'num' : ''}">${e(h)}</th>`).join('')}</tr></thead><tbody>${rows.map(row=>`<tr>${row}</tr>`).join('')}</tbody></table></div>` : noRows(label.toLowerCase().replace(/^(recent|latest) /,''));
}
function ledger(data) {
  const rows = data.recent_ledger || [];
  if (!rows.length && !data.ledger_totals.length) return noRows('ledger entries');
  const totals = data.ledger_totals.map(v=>`<tr><th scope="row" colspan="3">Total (${e(v.currency)})</th>${td('Currency',e(v.currency))}${td('Total debits',amount(v.debit),'num nonzero')}${td('Total credits',amount(v.credit),'num nonzero')}${td('Difference',amount(BigInt(v.debit)-BigInt(v.credit)),'num')}</tr>`).join('');
  return `<div class="overview-table-wrap ledger-preview"><table class="statement-table"><caption class="sr-only">Six newest ledger entries; lifetime totals by currency</caption><thead><tr>${['Entry','Timestamp (UTC)','Description','Currency','Debits','Credits','Difference'].map((h,i)=>`<th scope="col" class="${i>3 ? 'num' : ''}">${h}</th>`).join('')}</tr></thead><tbody>${rows.map(v=>`<tr>${td('Entry',`<span class="mono">${code('LE',v.id)}</span>`)}${td('Timestamp (UTC)',stamp(v.created_at),'timestamp')}${td('Description',`${invoiceLink(v.invoice_id)} · ${e(title(v.account))}`,'statement-description')}${td('Currency',e(v.currency))}${td('Debits',amount(v.debit),`num ${BigInt(v.debit) ? 'nonzero' : 'zero'}`)}${td('Credits',amount(v.credit),`num ${BigInt(v.credit) ? 'nonzero' : 'zero'}`)}${td('Entry difference',amount(BigInt(v.debit)-BigInt(v.credit)),'num')}</tr>`).join('')}</tbody><tfoot>${totals}</tfoot></table></div>`;
}
export function overview(data) {
  const counts = `<div class="stats-strip">${Object.entries(labels).map(([key,label])=>`<a class="stat" href="#${key}"><span>${label}</span><strong>${integer(data.counts[key])}</strong></a>`).join('')}</div>`;
  const invoices = table('Recent invoices',['Invoice','Customer','Amount','Status'],data.recent_invoices.map(v=>td('Invoice',invoiceLink(v.id))+td('Customer',`<span class="clipped" title="${e(v.customer_name)}">${customerLink(v)}</span>`)+td('Amount',`${e(v.currency)} ${amount(v.amount)}`,'num')+td('Status',status(v.status))));
  const webhooks = table('Webhook activity',['Event','Receipt','Received (UTC)','Status'],data.recent_webhooks.map(v=>td('Event',`<a class="record-link" href="#webhooks/${e(v.id)}">${e(v.event_type)}</a>`)+td('Receipt',`<a class="mono" title="${e(v.stripe_id)}" href="#webhooks/${e(v.id)}">${code('EVT',v.id)}</a>`)+td('Received (UTC)',stamp(v.created_at),'timestamp')+td('Status',status(v.status))));
  const customers = table('Customers',['Customer','ID','Created (UTC)'],data.recent_customers.map(v=>td('Customer',named(v))+td('ID',`<span class="mono">${code('CUS',v.id)}</span>`)+td('Created (UTC)',stamp(v.created_at),'timestamp')));
  const usage = table('Latest usage',['Event','Customer','Metric','Quantity'],data.recent_usage.map(v=>td('Event',`<a class="mono" href="#usage?customer_id=${e(v.customer_id)}">${code('USE',v.id)}</a>`)+td('Customer',`<span class="clipped" title="${e(v.customer_name)}">${customerLink(v)}</span>`)+td('Metric',e(v.metric))+td('Quantity',integer(v.quantity),'num')));
  return `${counts}<div class="overview-grid"><section class="panel overview-panel wide"><header class="panel-header"><div><h2>Ledger book (double-entry)</h2><p>Six newest entries. Lifetime totals by currency.</p></div>${seeAll('ledger')}</header>${ledger(data)}</section>${panel('Recent invoices','invoices','The latest recorded invoices.',invoices)}${panel('Webhook activity','webhooks','The latest stored Stripe deliveries.',webhooks)}${panel('Customers','customers','The latest customer records.',customers)}${panel('Latest usage','usage','The latest metered events.',usage)}</div>`;
}
