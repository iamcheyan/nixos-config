import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import MarkdownIt from 'markdown-it';

const root = process.cwd();
const source = path.join(root, 'site/src');
const output = path.join(root, 'site/dist');
const md = new MarkdownIt({ html: false, linkify: true, typographer: false, breaks: false });
const excluded = new Set(['AGENTS.md', 'modules/anchor-shell/AGENTS.md', 'docs/hx90-lockscreen-black-screen-incident.md']);
const excludedPrefixes = ['local/', 'logs/', 'hosts/hx90/hardware-configuration.nix', 'hosts/aarch64/hardware-configuration.nix', 'modules/packages/ai-usagebar/upstream/', 'modules/anchor-shell/compat/omarchy/'];
const upstreamPrefixes = ['modules/packages/ai-usagebar/upstream/', 'modules/anchor-shell/compat/omarchy/'];
const docs = [];

function walk(dir) {
  for (const item of fs.readdirSync(dir, { withFileTypes: true })) {
    const absolute = path.join(dir, item.name);
    if (item.isDirectory()) {
      if (dir === root && !['docs', 'modules', 'site'].includes(item.name)) continue;
      if (dir === path.join(root, 'site') && item.name !== 'src') continue;
      walk(absolute);
    } else if (item.name.endsWith('.md')) {
      const rel = path.relative(root, absolute).split(path.sep).join('/');
      if (rel.startsWith('site/src/') || (!excluded.has(rel) && !excludedPrefixes.some((prefix) => rel.startsWith(prefix)))) docs.push(rel);
    }
  }
}
walk(root);
for (const file of ['site/src/index.md', 'site/src/architecture.md', 'site/src/desktop.md', 'site/src/ownership.md', 'site/src/troubleshooting.md', 'site/src/local-boundary.md']) if (!docs.includes(file)) docs.push(file);
docs.sort((a,b)=>a.localeCompare(b));

function titleOf(text, rel) {
  return text.match(/^#\s+(.+)$/m)?.[1]?.replace(/`/g,'') || path.basename(rel, '.md');
}
function hrefFor(rel) { return `/${rel.replaceAll(' ', '%20').replace(/\.md$/i,'.html')}`; }
const urlFor=(rel)=>rel.startsWith('site/src/')?`/${path.basename(rel,'.md')}.html`:hrefFor(rel);
function sidebar(current) {
  const sections = [
    ['学习入口', ['site/src/index.md','README.md','site/src/architecture.md','docs/nixos-learning-notes.md','site/src/ownership.md','site/src/local-boundary.md','site/src/troubleshooting.md','site/src/desktop.md']],
    ['系统与日常操作', docs.filter(x=>x.startsWith('docs/')&&!x.startsWith('docs/macos-nix-darwin/')&&!x.startsWith('docs/nixarchy/'))],
    ['macOS / nix-darwin', docs.filter(x=>x.startsWith('docs/macos-nix-darwin/'))],
    ['桌面与 Anchor Shell', docs.filter(x=>x.startsWith('modules/anchor-shell/')||x.startsWith('modules/labwc/')||x==='site/src/desktop.md')],
    ['模块和其他指南', docs.filter(x=>x.startsWith('modules/')&&!x.startsWith('modules/anchor-shell/')&&!x.startsWith('modules/labwc/')&&!x.startsWith('modules/packages/ai-usagebar/upstream/')&&!x.startsWith('modules/anchor-shell/compat/omarchy/'))],
  ];
  const seen=new Set(); let html='';
  for (const [label, files] of sections) {
    const items=[...new Set(files)].filter(x=>docs.includes(x)&&!seen.has(x)); items.forEach(x=>seen.add(x));
    if (!items.length) continue;
    html+=`<details open><summary>${esc(label)} <span>${items.length}</span></summary><div class="side-items">${items.map(x=>`<a class="side-link ${x===current?'selected':''}" href="${urlFor(x)}" title="${esc(titleOf(fs.readFileSync(path.join(root,x),'utf8'),x))}">${esc(titleOf(fs.readFileSync(path.join(root,x),'utf8'),x))}</a>`).join('')}</div></details>`;
  }
  return html;
}
function esc(s){return String(s).replaceAll('&','&amp;').replaceAll('<','&lt;').replaceAll('>','&gt;').replaceAll('"','&quot;');}
function convertLinks(html, rel) {
  const base=path.posix.dirname('/'+rel);
  return html.replace(/href="([^"]+\.md(?:#[^"]*)?)"/g,(whole,target)=>{
    const [raw,hash='']=target.split('#',2);
    if (/^(https?:|mailto:|\/\/)/.test(raw)) return whole;
    if (rel.startsWith('site/src/')) {
      const repoTarget=raw.startsWith('../')
        ? path.posix.normalize('/'+raw.slice(3))
        : path.posix.normalize(path.posix.join('/site/src',raw));
      const repoSource=path.join(root,repoTarget.slice(1));
      if (!fs.existsSync(repoSource)) return whole;
      if (repoTarget.startsWith('/site/src/')) {
        const page=path.basename(repoTarget,'.md');
        return `href="${page==='index'?'/':`/${page}.html`}${hash?`#${hash}`:''}"`;
      }
      return `href="${hrefFor(repoTarget.slice(1))}${hash?`#${hash}`:''}"`;
    }
    const resolved=path.posix.normalize(path.posix.join(base,raw));
    if (resolved.startsWith('/site/src/')) {
      const targetSource=path.join(root,resolved.slice(1));
      if (!fs.existsSync(targetSource)) return whole;
      return `href="/${path.basename(resolved,'.md')}.html${hash?`#${hash}`:''}"`;
    }
    const absolute=path.join(root,resolved.slice(1));
    if (!fs.existsSync(absolute)) return whole;
    return `href="${hrefFor(resolved.slice(1))}${hash?`#${hash}`:''}"`;
  });
}
function breadcrumbs(rel){
 const parts=rel.split('/'); const out=[['首页','/']];
 if (parts[0]==='docs')out.push(['文档','/#网站内容']);
 if (parts[0]==='modules')out.push(['模块','/#共享模块地图']);
 if (parts[0]==='site')out.push(['学习手册','/']);
 if(parts.length>2){const readme=parts[0]==='site'?'README.md':hrefFor(parts.slice(0,2).join('/')+'/README.md');out.push([parts[1],readme]);}
 return out.map(([t,h])=>`<a href="${h}">${esc(t)}</a>`).join('<span> / </span>');
}
function shell(rel, title, content, isDoc=true){
 const nav=`<a href="/">学习首页</a><a href="/architecture.html">配置架构</a><a href="/desktop.html">桌面系统</a><a href="/troubleshooting.html">更新与排错</a>`;
 return `<!doctype html><html lang="zh-CN"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta name="color-scheme" content="light"><meta name="description" content="NixOS 配置学习手册：从真实 flake 学习主机、模块、桌面和安全更新。"><title>${esc(title)} · NixOS 配置学习手册</title><link rel="stylesheet" href="/site/assets/style.css"></head><body><header class="topbar"><a class="logo" href="/"><span class="logo-mark">N</span><span><b>NixOS</b><small>CONFIG HANDBOOK</small></span></a><nav>${nav}</nav><a class="github" href="https://github.com/iamcheyan/nixos-config">GitHub ↗</a><button class="menu-btn" aria-label="打开目录" id="menuBtn">目录</button></header><div class="layout"><aside class="sidebar" id="sidebar"><div class="side-label">配置学习路径</div><div class="searchbox"><span>⌕</span><input id="search" type="search" placeholder="搜索文档…" aria-label="搜索文档"><kbd>/</kbd></div><div id="searchResults" class="search-results"></div>${sidebar(rel)}<div class="sidebar-foot">来源：仓库文档与当前配置<br><a href="https://nixos.org/manual/nixos/stable/">NixOS 官方手册 ↗</a></div></aside><main><div class="content"><div class="breadcrumbs">${breadcrumbs(rel)}</div><article>${content}</article><footer class="page-foot"><span>以仓库源码为准 · 学习手册由配置仓库构建</span><a href="https://nixos.org/manual/nixos/stable/">NixOS 官方手册 ↗</a></footer></div></main></div><script src="/site/assets/app.js" defer></script></body></html>`;
}
fs.rmSync(output,{recursive:true,force:true});fs.mkdirSync(output,{recursive:true});
for(const rel of docs){
 const input=path.join(root,rel), text=fs.readFileSync(input,'utf8'), title=titleOf(text,rel);
 if (rel.startsWith('site/src/') && rel !== 'site/src/index.md' && rel !== 'site/src/architecture.md' && rel !== 'site/src/desktop.md' && rel !== 'site/src/ownership.md' && rel !== 'site/src/troubleshooting.md') {
   const rendered=md.render(text);
   const dest=path.join(output,hrefFor(rel).slice(1));fs.mkdirSync(path.dirname(dest),{recursive:true});fs.writeFileSync(dest,shell(rel,title,`<h1>${esc(title)}</h1><div class="doc-meta"><span>学习补充</span></div>${rendered}`));continue;
 }
 const rawHtml=md.render(text).replace(/file:\/\/[^\s"')>]*/g, match=>{
   const target=match.slice('file://'.length);
   const absolute=path.resolve(target);
   const relTarget=path.relative(root,absolute).split(path.sep).join('/');
   return `https://github.com/iamcheyan/nixos-config/blob/main/${relTarget}`;
 });
 const rendered=convertLinks(rawHtml,rel).replaceAll(`file://${root}`,'https://github.com/iamcheyan/nixos-config/blob/main').replaceAll(root,'~/nixos-config').replaceAll(path.join(os.homedir(),'development','labwc-plus'),'<labwc-plus checkout>').replace(/\/home\/[^/\s`"']+\/[^\s`"']+/g, '<home>/<path>').replaceAll('root/home/nix','root, home, and nix');
 const sidebarPage=['site/src/index.md','site/src/architecture.md','site/src/desktop.md','site/src/ownership.md','site/src/troubleshooting.md','site/src/local-boundary.md'].includes(rel);
 const isReadme=path.basename(rel).toLowerCase()==='readme.md';
 const body=`${sidebarPage?'':`<h1>${esc(title)}</h1><div class="doc-meta"><span>仓库文档</span><a href="https://github.com/iamcheyan/nixos-config/blob/main/${rel}">查看 GitHub 源文件 ↗</a></div>`}${isReadme?`<div class="callout">本节为 <code>${esc(path.dirname(rel))}</code> 的项目说明。先看下方摘要，再按需展开具体专题。</div><details class="full-doc"><summary>展开完整 README 原文</summary>${rendered}</details>`:rendered}`;
 const dest=path.join(output,hrefFor(rel).slice(1));fs.mkdirSync(path.dirname(dest),{recursive:true});fs.writeFileSync(dest,shell(rel,title,body));
}
const rootPages=['index','architecture','desktop','ownership','troubleshooting','local-boundary'];
for (const page of rootPages) {
  const sourcePage=path.join(output,'site/src',`${page}.html`);
  if (fs.existsSync(sourcePage)) fs.copyFileSync(sourcePage,path.join(output,`${page}.html`));
}
const upstream=upstreamPrefixes.flatMap(prefix=>{
 const base=path.join(root,prefix); if(!fs.existsSync(base))return [];
 const files=[];const visit=d=>{for(const e of fs.readdirSync(d,{withFileTypes:true})){const p=path.join(d,e.name);if(e.isDirectory())visit(p);else if(e.name.toLowerCase()==='readme.md')files.push(path.relative(root,p).split(path.sep).join('/'));}};visit(base);return files;
});
const searchCorpus=docs.filter(rel=>!rel.startsWith('site/src/'));
const index=searchCorpus.map(rel=>({path:hrefFor(rel),title:titleOf(fs.readFileSync(path.join(root,rel),'utf8'),rel),source:rel,section:rel.startsWith('docs/macos-nix-darwin/')?'macOS 与 nix-darwin':rel.startsWith('docs/')?'NixOS 与运维':rel.startsWith('modules/anchor-shell/')?'Anchor Shell':rel.startsWith('modules/labwc/')?'Labwc 与桌面':'模块与仓库'}));
fs.writeFileSync(path.join(output,'search-index.json'),JSON.stringify(index));
fs.mkdirSync(path.join(output,'site/assets'),{recursive:true});fs.copyFileSync(path.join(root,'site/src/style.css'),path.join(output,'site/assets/style.css'));fs.copyFileSync(path.join(root,'site/src/app.js'),path.join(output,'site/assets/app.js'));
for(const rel of ['CNAME','README.md']) if(fs.existsSync(path.join(root,rel)))fs.copyFileSync(path.join(root,rel),path.join(output,rel));
const outLinks=upstream.map(rel=>`<li><code>${esc(rel)}</code> — <a href="https://github.com/iamcheyan/nixos-config/tree/main/${rel.split('/').slice(0,-1).join('/')}">在 GitHub 浏览上游文档 ↗</a></li>`).join('');
const upstreamPage=`<h1>随包上游文档</h1><p>这些文档随引用的上游项目一起维护。为了保留来源和许可边界，本手册不复制其正文；请从 GitHub 查看当前版本。</p><ul>${outLinks}</ul>`;
fs.writeFileSync(path.join(output,'reference-upstream.html'),shell('reference-upstream.md','随包上游文档',upstreamPage));
const sourceCount=docs.filter(x=>!x.startsWith('site/src/')).length;
const result={markdownDocuments:sourceCount,handbookPages:docs.length-sourceCount,upstreamReadmes:upstream.length,generatedHtml:docs.length+1,excluded:[...excluded,...excludedPrefixes]};fs.writeFileSync(path.join(output,'build-report.json'),JSON.stringify(result,null,2));console.log(JSON.stringify(result));
