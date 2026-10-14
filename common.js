const cfg=window.LOTTERY_CONFIG;
if(!cfg || cfg.url.startsWith('YOUR_')) document.body.insertAdjacentHTML('afterbegin','<div class="card error">請先編輯 config.js，填入 Supabase URL 與 publishable key。</div>');
const db=window.supabase.createClient(cfg.url,cfg.publishableKey);
const $=id=>document.getElementById(id);
const err=e=>e?.message||String(e);
function escapeHTML(s){return String(s).replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));}
async function fetchState(){const {data,error}=await db.from('lottery_state').select('*').eq('id',1).single();if(error)throw error;return data;}
