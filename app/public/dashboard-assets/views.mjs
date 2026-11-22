import {escape as e, integer, money, title, date, time, code, status, invoiceLink, customerLink} from './format.mjs?v=1';

export const names = {overview:'Overview', customers:'Customers', usage:'Usage', invoices:'Invoices', ledger:'Ledger entries', webhooks:'Webhooks'};
export const icons = {
  overview:'<rect x="3" y="3" width="7" height="7" rx="1"/><rect x="14" y="3" width="7" height="7" rx="1"/><rect x="3" y="14" width="7" height="7" rx="1"/><rect x="14" y="14" width="7" height="7" rx="1"/>',
  customers:'<circle cx="9" cy="8" r="3"/><path d="M3 21v-3a6 6 0 0 1 12 0v3M16 5a3 3 0 0 1 0 6m5 10v-3a6 6 0 0 0-3-5"/>',
  usage:'<path d="M4 20h16M6 16v-5m6 5V4m6 12V8"/>',
  invoices:'<path d="M6 3h12v18l-3-2-3 2-3-2-3 2V3Zm3 5h6m-6 4h6"/>',
  ledger:'<path d="M4 4h16v16H4zM12 4v16M7 8h2m-2 4h2m6-4h2m-2 4h2"/>',
  webhooks:'<path d="m10 4-6 8 6 8m4-16 6 8-6 8M8 12h8"/>',
  refresh:'<path d="M20 7v5h-5M4 17v-5h5"/><path d="M6 7a7 7 0 0 1 12-1l2 3M4 15l2 3a7 7 0 0 0 12-1"/>',
  arrow:'<path d="M5 12h14m-5-5 5 5-5 5"/>',
  search:'<circle cx="10" cy="10" r="6"/><path d="m15 15 6 6"/>',
  menu:'<path d="M4 6h16M4 12h16M4 18h16"/>',
  close:'<path d="m6 6 12 12M6 18 18 6"/>'
};
export const icon = name => `<svg viewBox="0 0 24 24" width="16" height="16" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${icons[name] || icons.arrow}</svg>`;
export const empty = (heading, text) => `<div class="empty-state"><strong>${e(heading)}</strong><p>${e(text)}</p></div>`;
const panel = (heading, content, link='', note='') => `<section class="panel"><header class="panel-header"><div><h2>${e(heading)}</h2>${note ? `<p>${e(note)}</p>` : ''}</div>${link}</header>${content}</section>`;
const all = section => `<a class="text-link" href="#${section}">View all</a>`;
export {overview} from './overview.mjs?v=1';

export const statusChoices = {usage:['billed','unbilled'], invoices:['issued','paid','payment_failed','refunded'], webhooks:['received','processed','ignored','review','dead']};
export function toolbar(section, params) {
  const filters = Object.entries(params).filter(([k]) => k !== 'page' && k !== 'per_page');
  return `<form id="filters" class="toolbar" role="search"><label class="search-box"><span class="sr-only">Search ${names[section].toLowerCase()}</span>${icon('search')}<input id="search" name="q" type="search" maxlength="100" placeholder="Search ${names[section].toLowerCase()}…" value="${e(params.q || '')}"></label>${statusChoices[section] ? `<label class="sr-only" for="status-filter">Status</label><select id="status-filter" name="status"><option value="">All statuses</option>${statusChoices[section].map(v => `<option value="${v}" ${params.status === v ? 'selected' : ''}>${e(title(v))}</option>`).join('')}</select>` : ''}${filters.length ? '<button class="button" type="button" data-clear>Clear filters</button>' : ''}</form>`;
}
const cell = (label, value, cls='') => `<td data-label="${e(label)}" class="${cls}">${value}</td>`;
const action = (section,id,label) => cell('Open',`<a class="row-action" href="#${section}/${e(id)}" aria-label="${e(label)}">${icon('arrow')}</a>`,'actions');
const secondary = value => `<span class="subline">${value}</span>`;
const schema = {
  customers: {heads:['Customer','Stripe customer','Created',''], render:v => cell('Customer',`<a class="record-link" href="#customers/${e(v.id)}">${e(v.name)}</a>${secondary(e(v.email))}`)+cell('Stripe customer',e(v.stripe_customer_id || 'Not linked'),'mono')+cell('Created',date(v.created_at))+action('customers',v.id,`Open ${v.name}`)},
  usage: {heads:['Metric','Customer','Quantity','Occurred (UTC)','Invoice'],render:v => cell('Metric',`${e(v.metric)}${secondary(code('USE',v.id))}`)+cell('Customer',customerLink(v))+cell('Quantity',integer(v.quantity),'num')+cell('Occurred (UTC)',time(v.occurred_at))+cell('Invoice',v.invoice_id ? invoiceLink(v.invoice_id) : status('unbilled'))},
  invoices: {heads:['Invoice','Customer','Billing period','Amount','Status',''],render:v => cell('Invoice',invoiceLink(v.id))+cell('Customer',customerLink(v))+cell('Billing period',`${date(v.period_start)}${secondary(`to ${date(v.period_end)} (exclusive)`)}`)+cell('Amount',money(v.amount,v.currency),'num')+cell('Status',status(v.status))+action('invoices',v.id,`Open invoice ${v.id}`)},
  ledger: {heads:['Journal / invoice','Account','Debit','Credit','Recorded (UTC)'],render:v => cell('Journal / invoice',`<span class="mono">${code('JRN',v.journal_id)}</span>${secondary(`${e(title(v.journal_type))} · ${invoiceLink(v.invoice_id)}`)}`)+cell('Account',e(title(v.account)))+cell('Debit',money(v.debit,v.currency),'num')+cell('Credit',money(v.credit,v.currency),'num')+cell('Recorded (UTC)',time(v.created_at))},
  webhooks: {heads:['Event','Status','Attempts','Received (UTC)',''],render:v => cell('Event',`<a class="record-link" href="#webhooks/${e(v.id)}">${e(v.event_type)}</a>${secondary(`<span class="mono">${e(v.stripe_id)}</span>`)}`)+cell('Status',status(v.status))+cell('Attempts',integer(v.attempts),'num')+cell('Received (UTC)',time(v.created_at))+action('webhooks',v.id,`Inspect ${v.stripe_id}`)}
};
export function table(section, rows) {
  const {heads,render} = schema[section];
  return `<div class="table-wrap"><table class="data-table"><caption class="sr-only">${names[section]}</caption><thead><tr>${heads.map(v => `<th scope="col" class="${['Amount','Quantity','Debit','Credit','Attempts'].includes(v) ? 'num' : ''}">${e(v)}</th>`).join('')}</tr></thead><tbody>${rows.map(v => `<tr>${render(v)}</tr>`).join('')}</tbody></table></div>`;
}
export function collection(section, payload, params) {
  const {data,meta} = payload, start=(meta.page-1)*meta.per_page+1, end=Math.min(meta.total,start+data.length-1), pages=Math.max(1,Math.ceil(meta.total/meta.per_page));
  const scoped = params.customer_id ? `Customer ${code('CUS',params.customer_id)}` : params.invoice_id ? code('INV',params.invoice_id) : params.stripe_event_id ? code('EVT',params.stripe_event_id) : 'All records';
  return `${toolbar(section,params)}<section class="panel"><div class="table-top"><span class="record-count">${integer(meta.total)} ${section === 'usage' ? 'usage events' : names[section].toLowerCase()}</span><span class="scope-label">${e(scoped)}</span></div>${data.length ? table(section,data) : empty('No matching records',Object.keys(params).some(k => k !== 'page') ? 'Try another search or clear the filters.' : 'Records will appear here when the API receives them.')}<div class="pagination"><span>${data.length ? `${integer(start)}–${integer(end)} of ${integer(meta.total)}` : '0 records on this page'}</span><div class="pagination-controls"><button class="button" data-page="${meta.page-1}" ${meta.page <= 1 ? 'disabled' : ''}>Previous</button><span>Page ${integer(meta.page)} of ${integer(pages)}</span><button class="button" data-page="${meta.page+1}" ${meta.page >= pages ? 'disabled' : ''}>Next</button></div></div></section>`;
}
const kv = pairs => `<dl class="key-values">${pairs.map(([k,v]) => `<div><dt>${e(k)}</dt><dd>${v}</dd></div>`).join('')}</dl>`;
const linkButton = (hash,label) => `<a class="button" href="#${hash}">${icon('arrow')}${e(label)}</a>`;

export function customer(v) {
  return `<div class="detail-grid"><div class="detail-stack">${panel('Activity',`<div class="detail-stats"><a href="#invoices?customer_id=${e(v.id)}"><span>Invoices</span><strong>${integer(v.invoice_count)}</strong></a><a href="#usage?customer_id=${e(v.id)}"><span>Usage events</span><strong>${integer(v.usage_count)}</strong></a></div>`)}${panel('Receivable balances',v.balances.length ? kv(v.balances.map(b => [b.currency,money(b.amount,b.currency)])) : empty('No balances yet','No receivable postings exist for this customer.'),'','Negative balances indicate a credit. Currencies are not combined.')}</div>${panel('Customer record',kv([['Customer ID',`<span class="mono">${code('CUS',v.id)}</span>`],['Email',e(v.email)],['Stripe customer',`<span class="mono">${e(v.stripe_customer_id || 'Not linked')}</span>`],['Created',date(v.created_at)]])+`<div class="detail-actions">${linkButton(`usage?customer_id=${v.id}`,'View usage')}${linkButton(`invoices?customer_id=${v.id}`,'View invoices')}${linkButton(`ledger?customer_id=${v.id}`,'View ledger entries')}</div>`)}</div>`;
}
export function invoice(v, entries) {
  const lines = v.line_items.length ? `<div class="table-wrap"><table class="data-table"><caption class="sr-only">Invoice line items</caption><thead><tr><th>Metric</th><th class="num">Quantity</th><th class="num">Unit price</th><th class="num">Amount</th></tr></thead><tbody>${v.line_items.map(l => `<tr>${cell('Metric',e(l.metric))}${cell('Quantity',integer(l.quantity),'num')}${cell('Unit price',money(l.unit_amount,v.currency),'num')}${cell('Amount',money(l.amount,v.currency),'num')}</tr>`).join('')}</tbody></table></div>` : empty('No line items','This invoice has no stored line items.');
  return `<div class="detail-grid"><div class="detail-stack">${panel('Invoice line items',lines,'',`${integer(v.line_item_count)} line items${v.line_item_count > 100 ? ' · showing the first 100' : ''}`)}${panel('Journal entries',entries.data.length ? table('ledger',entries.data) : empty('No journal entries','No postings are linked to this invoice.'),`<a class="text-link" href="#ledger?invoice_id=${e(v.id)}">View all</a>`,`${integer(v.journal_count)} journals · ${integer(entries.meta.total)} entries${entries.meta.total > 25 ? ' · showing the newest 25' : ''}`)}</div>${panel('Invoice record',kv([['Invoice',`<span class="mono">${code('INV',v.id)}</span>`],['Customer',customerLink(v)],['Status',status(v.status)],['Period starts',date(v.period_start)],['Period ends',`${date(v.period_end)} (exclusive)`],['Stripe invoice',`<span class="mono">${e(v.stripe_invoice_id || 'Not linked')}</span>`]])+`<div class="detail-total"><span>Total issued</span>${money(v.amount,v.currency)}</div>`)}</div>`;
}
export function webhook(v, entries) {
  const steps = [['Received',v.created_at,'Stored after signature verification.'],['Dispatched',v.dispatched_at,'Sent to the background queue.'],['Processed',v.processed_at,'Processing completion recorded.']];
  return `<div class="detail-grid"><div class="detail-stack">${panel('Processing timeline',`<div class="event-timeline">${steps.map(([label,at,note]) => `<div class="event-step ${at ? 'done' : ''}"><span class="step-dot" aria-hidden="true"></span><div><strong>${label}</strong><p>${at ? `${time(at)} UTC · ${e(note)}` : 'No timestamp recorded.'}</p></div></div>`).join('')}</div>`)}${v.last_error ? panel('Last recorded error',`<p class="detail-message full-id mono">${e(v.last_error)}</p>`) : ''}${panel('Related ledger entries',entries.data.length ? table('ledger',entries.data) : empty('No financial postings','Ignored, duplicate, pending or review events may have no journal.'),`<a class="text-link" href="#ledger?stripe_event_id=${e(v.id)}">View all</a>`,`${integer(entries.meta.total)} entries linked to this stored event`)}</div>${panel('Webhook record',kv([['Stripe event',`<span class="mono full-id">${e(v.stripe_id)}</span>`],['Type',e(v.event_type)],['Status',status(v.status)],['Attempts',integer(v.attempts)],['Last attempt',time(v.last_attempted_at)],['API version',`<span class="mono">${e(v.api_version || 'Not provided')}</span>`]])+'<p class="detail-message">Raw webhook payloads are excluded from the dashboard. Replays and retries remain operator-only actions.</p>')}</div>`;
}
