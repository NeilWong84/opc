const ids=[];
const fonts=[['Noto Sans JP','Regular'],['Noto Sans JP','Medium'],['Noto Sans JP','Bold'],['Noto Sans SC','Regular'],['Noto Sans SC','Bold'],['Plus Jakarta Sans','Bold'],['Plus Jakarta Sans','Medium']];
await Promise.all(fonts.map(([family,style])=>figma.loadFontAsync({family,style})));
const vars=Object.fromEntries((await figma.variables.getLocalVariablesAsync()).map(v=>[v.name,v]));
const styles=Object.fromEntries((await figma.getLocalTextStylesAsync()).filter(s=>s.name.startsWith('OPC / ')).map(s=>[s.name.slice(6),s.id]));
function track(n){ids.push(n.id);return n;}
function paint(k){return [figma.variables.setBoundVariableForPaint({type:'SOLID',color:{r:1,g:1,b:1}},'color',vars['color/'+k])];}
function rad(n,v){n.cornerRadius=v;const vr=vars['radius/'+v];if(vr)for(const p of ['topLeftRadius','topRightRadius','bottomLeftRadius','bottomRightRadius'])n.setBoundVariable(p,vr);}
function pad(n,v){for(const p of ['paddingTop','paddingBottom','paddingLeft','paddingRight']){n[p]=v;if(vars['space/'+v])n.setBoundVariable(p,vars['space/'+v]);}}
function gap(n,v){n.itemSpacing=v;if(vars['space/'+v])n.setBoundVariable('itemSpacing',vars['space/'+v]);}
function box(p,name,w,dir='VERTICAL',g=12,bg=null,padding=0){const n=track(figma.createAutoLayout(dir));n.name=name;p.appendChild(n);n.resize(w,40);n.primaryAxisSizingMode=dir==='VERTICAL'?'AUTO':'FIXED';n.counterAxisSizingMode=dir==='VERTICAL'?'FIXED':'AUTO';n.fills=bg?paint(bg):[];gap(n,g);pad(n,padding);return n;}
function txt(p,str,style='Body',color='text',w=null){const n=track(figma.createText());n.name=str.slice(0,40);n.textStyleId=styles[style];n.fills=paint(color);if(w){n.textAutoResize='HEIGHT';n.resize(w,22);n.textAutoResize='HEIGHT';}else n.textAutoResize='WIDTH_AND_HEIGHT';n.characters=str;p.appendChild(n);return n;}
function rect(p,w,h,col,r=0){const n=track(figma.createRectangle());n.name='Shape';p.appendChild(n);n.resize(w,h);n.fills=paint(col);if(r)rad(n,r);return n;}
function line(p,w){return rect(p,w,1,'border');}
function fixed(n,w,h){n.resize(w,h);n.primaryAxisSizingMode='FIXED';n.counterAxisSizingMode='FIXED';}
function prop(c,t,name){const k=c.addComponentProperty(name,'TEXT',t.characters);t.componentPropertyReferences={characters:k};return k;}
function comp(parent,name,w,h,dir='VERTICAL',bg='surface'){const c=track(figma.createComponent());c.name=name;c.description='OPC Japanese mobile V1 reusable '+name;c.layoutMode=dir;c.resize(w,h);c.fills=paint(bg);parent.appendChild(c);return c;}
function icon(p,name,color='secondary',size=22){const paths={
 code:'<path d="m8 6-6 6 6 6M16 6l6 6-6 6M14 4l-4 16"/>',
 grid:'<rect x="3" y="3" width="7" height="7" rx="2"/><rect x="14" y="3" width="7" height="7" rx="2"/><rect x="3" y="14" width="7" height="7" rx="2"/><rect x="14" y="14" width="7" height="7" rx="2"/>',
 folder:'<path d="M3 7V5a2 2 0 0 1 2-2h5l2 3h7a2 2 0 0 1 2 2v11a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z"/>',
 check:'<path d="m5 12 4 4L19 6"/>',plus:'<path d="M12 5v14M5 12h14"/>',
 search:'<circle cx="10.5" cy="10.5" r="6.5"/><path d="m16 16 5 5"/>',
 clock:'<circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/>',
 doc:'<path d="M14 3H6a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V9zM14 3v6h6M8 13h8M8 17h5"/>',
 arrow:'<path d="M4 12h16m-6-6 6 6-6 6"/>',
 chevron:'<path d="m9 5 7 7-7 7"/>',
 shield:'<path d="m12 2 8 4v6c0 5-8 10-8 10S4 17 4 12V6z"/><path d="m8 12 3 3 5-6"/>',
 bell:'<path d="M18 8a6 6 0 0 0-12 0c0 7-3 7-3 9h18c0-2-3-2-3-9M10 21h4"/>',
 link:'<path d="m10 13 4-4M8 16l-2 2a4 4 0 0 1-6-6l4-4m12 0 2-2a4 4 0 0 1 6 6l-4 4"/>',
 sparkle:'<path d="m12 3 2.5 6.5L21 12l-6.5 2.5L12 21l-2.5-6.5L3 12l6.5-2.5z"/>'
};const svg='<svg width="'+size+'" height="'+size+'" viewBox="0 0 24 24" fill="none" stroke="#647572" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round" xmlns="http://www.w3.org/2000/svg">'+(paths[name]||paths.code)+'</svg>';const n=track(figma.createNodeFromSvg(svg));n.name='Icon/'+name;p.appendChild(n);for(const v of n.findAllWithCriteria({types:['VECTOR']})){if(v.strokes.length)v.strokes=paint(color);ids.push(v.id);}return n;}
