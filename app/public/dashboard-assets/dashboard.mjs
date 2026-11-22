import {escape as e, title, code} from './format.mjs?v=1';
import * as views from './views.mjs?v=1';

const $ = selector => document.querySelector(selector);
const content = $('#content'), notice = $('#notice'), refresh = $('#refresh');
let current, controller, sequence=0, counts, timer;
$('.skip-link').addEventListener('click', event => {
  event.preventDefault();
  $('#main').focus();
});
refresh.innerHTML = `${views.icon('refresh')}<span>Refresh</span>`;
refresh.setAttribute('aria-label','Refresh dashboard data');
$('#menu-toggle').innerHTML = views.icon('menu');

function navigation(section) {
  const attention = (counts?.webhook_states?.dead || 0)+(counts?.webhook_states?.review || 0);
  $('#navigation').innerHTML = Object.entries(views.names).map(([key,label]) => `<a href="#${key}" ${section === key ? 'aria-current="page"' : ''}>${views.icon(key)}<span>${label}</span>${key === 'webhooks' && attention > 0 ? `<span class="count" aria-label="${attention} events in dead or review status">${attention}</span>` : ''}</a>`).join('');
}
function route() {
  const [path,query=''] = location.hash.slice(1).split('?');
  const [section='overview',id] = (path || 'overview').split('/');
  return {section,id,params:Object.fromEntries(new URLSearchParams(query))};
}
function navigate(params) {
  const search = new URLSearchParams(Object.entries(params).filter(([,v]) => v !== '' && v != null));
  location.hash = `${current.section}${search.size ? `?${search}` : ''}`;
}
async function fetchData(path,signal) {
  const response = await fetch(`/dashboard/data/${path}`,{headers:{Accept:'application/json'},credentials:'same-origin',signal});
  if (response.status === 401) {
    content.replaceChildren();
    location.assign('/dashboard/login');
    throw new Error('Your viewing session expired. Sign in again.');
  }
  const payload = await response.json();
  if (!response.ok) throw new Error(payload.error?.message || 'The records could not be loaded. Try again.');
  return payload;
}
const descriptions = {overview:'A clear view of your recorded billing activity.',customers:'Customer records and their billing history.',usage:'Metered events, exactly as recorded.',invoices:'Issued invoices and their payment state.',ledger:'Every debit and credit, with its source invoice.',webhooks:'Stripe event receipts and processing status.'};
function header(section,detail) {
  $('#page-title').textContent = detail || views.names[section] || 'Page not found';
  $('#page-description').textContent = descriptions[section] || 'Choose a section from the navigation.';
  $('#breadcrumbs').innerHTML = detail ? `<a href="#${section}">${e(views.names[section])}</a><span>/</span>Record` : '';
  document.title = `${detail || views.names[section] || 'Page not found'} · Ledgerly`;
}
async function load(manual=false) {
  const target = route(), request=++sequence;
  controller?.abort(); controller=new AbortController();
  const signal=controller.signal;
  const sameRoute = current && JSON.stringify(current) === JSON.stringify(target);
  const changedPage = !current || current.section !== target.section || current.id !== target.id;
  current=target; navigation(target.section); header(target.section);
  if (!(manual && sameRoute)) content.innerHTML='<div class="loading-state" role="status">Loading records…</div>';
  notice.replaceChildren(); content.setAttribute('aria-busy','true'); refresh.disabled=true;
  try {
    if (!views.names[target.section]) throw new Error('This page does not exist. Choose a section from the navigation.');
    let html;
    if (target.section === 'overview') {
      const {data} = await fetchData('overview',signal); counts=data; html=views.overview(data);
    } else if (target.id) {
      if (!['customers','invoices','webhooks'].includes(target.section) || !/^\d+$/.test(target.id)) throw new Error('This record does not exist.');
      const {data} = await fetchData(`${target.section}/${encodeURIComponent(target.id)}`,signal);
      const name = target.section === 'customers' ? data.name : target.section === 'invoices' ? code('INV',data.id) : data.event_type;
      header(target.section,name);
      if (target.section === 'customers') html=views.customer(data);
      else {
        const key=target.section === 'invoices' ? 'invoice_id' : 'stripe_event_id';
        const entries=await fetchData(`ledger?${key}=${encodeURIComponent(data.id)}`,signal);
        html=views[target.section === 'invoices' ? 'invoice' : 'webhook'](data,entries);
      }
    } else {
      const payload=await fetchData(`${target.section}?${new URLSearchParams(target.params)}`,signal);
      html=views.collection(target.section,payload,target.params);
    }
    if (request !== sequence) return;
    content.innerHTML=html; navigation(target.section);
    if(changedPage) { window.scrollTo({top:0,behavior:'instant'}); $('#main').focus({preventScroll:true}); }
    $('#freshness').textContent=`Read at ${new Date().toISOString().slice(0,19).replace('T',' ')} UTC`;
    if (target.params.q && document.activeElement === document.body) {
      const input=$('#search'); input?.focus({preventScroll:true}); input?.setSelectionRange(input.value.length,input.value.length);
    }
  } catch (error) {
    if (error.name === 'AbortError' || request !== sequence) return;
    if (!(manual && sameRoute)) content.innerHTML=views.empty('Unable to load this view',error.message);
    notice.innerHTML=`<div class="notice" role="alert"><span>${e(manual && sameRoute ? 'Refresh failed. Previously loaded data is still shown. ' : '')}${e(error.message)}</span><button data-retry type="button">Try again</button></div>`;
  } finally {
    if (request === sequence) { content.setAttribute('aria-busy','false'); refresh.disabled=false; }
  }
}
refresh.addEventListener('click',() => load(true));
notice.addEventListener('click',event => {if (event.target.closest('[data-retry]')) load(true);});
content.addEventListener('click',event => {
  const page=event.target.closest('[data-page]');
  if (page && !page.disabled) navigate({...current.params,page:page.dataset.page});
  if (event.target.closest('[data-clear]')) navigate({});
});
content.addEventListener('submit',event => {if(event.target.id === 'filters') {event.preventDefault(); clearTimeout(timer); navigate({...current.params,...Object.fromEntries(new FormData(event.target)),page:1});}});
content.addEventListener('change',event => {if(event.target.id === 'status-filter') navigate({...current.params,status:event.target.value,page:1});});
content.addEventListener('input',event => {
  if(event.target.id !== 'search') return;
  clearTimeout(timer);
  const value=event.target.value;
  timer=setTimeout(() => navigate({...current.params,q:value,page:1}),350);
});
function menu(open) {
  document.body.classList.toggle('nav-open',open);
  $('#menu-toggle').setAttribute('aria-expanded',String(open));
  $('#menu-toggle').setAttribute('aria-label',`${open ? 'Close' : 'Open'} navigation`);
  $('#menu-toggle').innerHTML=views.icon(open ? 'close' : 'menu');
  $('#main').inert=open;
  $('#sidebar').inert=matchMedia('(max-width:1100px)').matches && !open;
  if(open) $('#navigation a')?.focus();
}
$('#menu-toggle').addEventListener('click',() => menu(!document.body.classList.contains('nav-open')));
$('#nav-scrim').addEventListener('click',() => menu(false));
$('#navigation').addEventListener('click',event => {if(event.target.closest('a')) menu(false);});
document.addEventListener('keydown',event => {
  if (!document.body.classList.contains('nav-open')) return;
  if (event.key === 'Escape') {menu(false); $('#menu-toggle').focus();}
  if (event.key === 'Tab') {
    const items=[$('#menu-toggle'),...$('#sidebar').querySelectorAll('a[href],button')].filter(v => v.getClientRects().length);
    const index=items.indexOf(document.activeElement);
    if (event.shiftKey && index <= 0) {event.preventDefault();items.at(-1).focus();}
    if (!event.shiftKey && index === items.length-1) {event.preventDefault();items[0].focus();}
  }
});
matchMedia('(min-width:1101px)').addEventListener('change',() => menu(false));
menu(false);
window.addEventListener('hashchange',() => {clearTimeout(timer);load();});
load();
