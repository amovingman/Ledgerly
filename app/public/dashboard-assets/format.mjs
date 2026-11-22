export const escape = value => String(value ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
export const integer = value => new Intl.NumberFormat('en-US').format(BigInt(value ?? 0));
export function amount(value) {
  const n = BigInt(value ?? 0), absolute = n < 0n ? -n : n;
  return `${n < 0n ? '−' : ''}${integer(absolute / 100n)}.${String(absolute % 100n).padStart(2, '0')}`;
}
export const money = (value, currency) => `<span class="money ${BigInt(value ?? 0) === 0n ? 'zero' : ''}"><span class="currency">${escape(currency)}</span> ${amount(value)}</span>`;
export const title = value => String(value ?? '').replace(/_/g, ' ').replace(/^./, c => c.toUpperCase());
export const date = value => value ? new Intl.DateTimeFormat('en-US', {day:'numeric', month:'short', year:'numeric', timeZone:'UTC'}).format(new Date(value)) : '—';
export const time = value => value ? new Intl.DateTimeFormat('en-GB', {day:'2-digit', month:'short', hour:'2-digit', minute:'2-digit', timeZone:'UTC'}).format(new Date(value)) : '—';
export const code = (prefix, id) => `${prefix}-${String(id).padStart(6, '0')}`;
export function status(value) {
  const good = ['paid','processed','billed'].includes(value);
  const bad = ['dead','payment_failed'].includes(value);
  const warn = ['review','received','unbilled'].includes(value);
  return `<span class="status ${good ? 'positive' : bad ? 'negative' : warn ? 'warning' : 'neutral'}"><span class="status-dot" aria-hidden="true"></span>${escape(title(value))}</span>`;
}
export const invoiceLink = id => `<a href="#invoices/${encodeURIComponent(id)}" class="record-link mono">${code('INV', id)}</a>`;
export const customerLink = row => `<a href="#customers/${encodeURIComponent(row.customer_id)}" class="record-link">${escape(row.customer_name)}</a>`;
