const q=(s,r=document)=>r.querySelector(s);const sidebar=q('#sidebar');q('#menuBtn')?.addEventListener('click',()=>sidebar.classList.toggle('open'));document.addEventListener('click',e=>{if(sidebar?.classList.contains('open')&&!sidebar.contains(e.target)&&e.target.id!=='menuBtn')sidebar.classList.remove('open')});document.addEventListener('keydown',e=>{if(e.key==='/'&&document.activeElement?.tagName!=='INPUT'){e.preventDefault();q('#search')?.focus()}if(e.key==='Escape'){q('#search')?.blur();sidebar?.classList.remove('open')}});

const themeKey='nixos-handbook-theme';const rootEl=document.documentElement;const themeBtn=q('#themeToggle');const media=window.matchMedia?window.matchMedia('(prefers-color-scheme: dark)'):null;
const storedTheme=()=>{try{const v=localStorage.getItem(themeKey);return v==='dark'||v==='light'?v:null}catch{return null}};
const effective=()=>rootEl.dataset.theme==='dark'?'dark':'light';
function syncThemeButton(){const dark=effective()==='dark';document.querySelector('meta[name="theme-color"]')?.setAttribute('content',dark?'#181a1d':'#ffffff');if(!themeBtn)return;themeBtn.setAttribute('aria-pressed',String(dark));const label=dark?'切换到日间模式':'切换到夜间模式';themeBtn.setAttribute('aria-label',label);themeBtn.title=label}
function applyTheme(mode,persist){rootEl.dataset.theme=mode==='dark'?'dark':'light';if(persist){try{localStorage.setItem(themeKey,rootEl.dataset.theme)}catch{}}syncThemeButton()}
applyTheme(effective(),false);
themeBtn?.addEventListener('click',()=>applyTheme(effective()==='dark'?'light':'dark',true));
media?.addEventListener?.('change',event=>{if(!storedTheme())applyTheme(event.matches?'dark':'light',false)});
syncThemeButton();

const input=q('#search'),results=q('#searchResults');let entries=[];fetch('/search-index.json').then(r=>r.json()).then(x=>entries=x).catch(()=>{});input?.addEventListener('input',()=>{const term=input.value.trim().toLocaleLowerCase('zh-CN');if(!term){results.classList.remove('show');results.innerHTML='';return}const found=entries.filter(x=>(x.title+' '+x.source+' '+x.section).toLocaleLowerCase('zh-CN').includes(term)).slice(0,30);results.innerHTML=found.map(x=>`<a class="search-result" href="${x.path}"><b>${x.title.replaceAll('&','&amp;').replaceAll('<','&lt;')}</b><small>${x.section} · ${x.source}</small></a>`).join('')||'<small class="search-empty">没有找到匹配文档</small>';results.classList.add('show')});
