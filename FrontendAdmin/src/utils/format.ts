export function formatJst(value:string, short=false) {
  const date=new Date(value);
  if(Number.isNaN(date.getTime())) return value;
  return new Intl.DateTimeFormat('ja-JP',{timeZone:'Asia/Tokyo',...(short?{}:{year:'numeric'}),month:'2-digit',day:'2-digit',hour:'2-digit',minute:'2-digit',hour12:false}).format(date)+(short?'':' JST');
}
