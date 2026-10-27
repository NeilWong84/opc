const componentIds={"buttonPrimary":"6:4","buttonSecondary":"6:6","buttonDisabled":"6:8","field":"6:11","badgeGreen":"6:15","badgeAmber":"6:17","badgeBlue":"6:19","badgeGray":"6:21","task":"6:24","nav":"6:37"};
const componentNodes=await Promise.all(Object.values(componentIds).map(id=>figma.getNodeByIdAsync(id)));
const components=Object.fromEntries(Object.keys(componentIds).map((k,i)=>[k,componentNodes[i]]));
function instance(p,key,values={}){const n=track(components[key].createInstance());p.appendChild(n);const resolved={};for(const [k,v]of Object.entries(values)){const real=Object.keys(n.componentProperties).find(x=>x===k||x.startsWith(k+'#'));if(real)resolved[real]=v;}if(Object.keys(resolved).length)n.setProperties(resolved);return n;}
function button(p,label,tone='Primary',w=350){const n=instance(p,'button'+tone,{Label:label});n.resize(w,52);return n;}
function badge(p,label,tone='Green'){return instance(p,'badge'+tone,{Label:label});}
function field(p,label,value){return instance(p,'field',{Label:label,Value:value});}
function card(p,name,w=350,bg='surface',padding=16,g=12){const n=box(p,name,w,'VERTICAL',g,bg,padding);rad(n,16);if(bg==='surface'){n.strokes=paint('border');n.strokeWeight=1;}return n;}
function row(p,name,w=350,g=8){const n=box(p,name,w,'HORIZONTAL',g);n.counterAxisAlignItems='CENTER';return n;}
function pair(p,l,r,w=318){const n=row(p,'Key / Value',w);n.primaryAxisAlignItems='SPACE_BETWEEN';txt(n,l,'Small','secondary');txt(n,r,'Small','text');return n;}
function note(p,str,bg='subtle',col='secondary'){const n=card(p,'Notice',350,bg,12,8);txt(n,str,'Small',col,326);return n;}
function tagrow(p,labels){const r=row(p,'Tags',350,8);for(const t of labels)badge(r,t,'Gray');return r;}
function bullet(p,str,w=318,col='text'){const r=row(p,'Checklist item',w,8);icon(r,'check','brand',18);txt(r,str,'Body',col,w-26);return r;}
function progress(p,labels,index){const n=row(p,'Step indicator',350,6);for(let i=0;i<labels.length;i++){const cell=box(n,'Step/'+i,Math.floor((350-(labels.length-1)*6)/labels.length),'VERTICAL',6);rect(cell,cell.width,4,i<=index?'brand':'border',0);txt(cell,labels[i],'Micro',i===index?'brand':'secondary');}return n;}
