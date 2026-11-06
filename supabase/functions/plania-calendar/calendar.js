// RFC 5545: stable identifiers, UTC instants, local dates and UTF-8 line folding.
const escapeText=value=>String(value??'').replace(/\\/g,'\\\\').replace(/\r\n|\r|\n/g,'\\n').replace(/;/g,'\\;').replace(/,/g,'\\,');
const instant=value=>new Date(value).toISOString().replace(/[-:]/g,'').replace(/\.\d{3}Z$/,'Z');
function dateOnly(value,timezone){const parts=new Intl.DateTimeFormat('en-US',{timeZone:timezone,year:'numeric',month:'2-digit',day:'2-digit'}).formatToParts(new Date(value));return ['year','month','day'].map(k=>parts.find(p=>p.type===k).value).join('')}
function fold(line){let out='',part='',bytes=0;for(const char of line){const n=new TextEncoder().encode(char).length;if(bytes+n>75){out+=part+'\r\n';part=' ';bytes=1}part+=char;bytes+=n}return out+part}
export function subscriptionCalendar(events,timezone='Europe/Madrid'){
 const lines=['BEGIN:VCALENDAR','VERSION:2.0','PRODID:-//PlanIA//Suscripcion//ES','CALSCALE:GREGORIAN','METHOD:PUBLISH','X-WR-CALNAME:PlanIA','REFRESH-INTERVAL;VALUE=DURATION:PT1H','X-PUBLISHED-TTL:PT1H'];
 for(const e of events){if(e.deleted_at||e.status==='cancelled')continue;const modified=e.updated_at||e.created_at||e.starts_at;
 lines.push('BEGIN:VEVENT',`UID:${e.id}@plania`,`DTSTAMP:${instant(modified)}`,`LAST-MODIFIED:${instant(modified)}`,`SEQUENCE:${Math.max(0,Math.floor(new Date(modified).getTime()/1000))}`,`SUMMARY:${escapeText(e.title)}`,`DESCRIPTION:${escapeText(e.description)}`);
 if(e.category)lines.push(`CATEGORIES:${escapeText(e.category)}`);
 if(e.all_day)lines.push(`DTSTART;VALUE=DATE:${dateOnly(e.starts_at,timezone)}`,`DTEND;VALUE=DATE:${dateOnly(e.ends_at,timezone)}`);
 else lines.push(`DTSTART:${instant(e.starts_at)}`,`DTEND:${instant(e.ends_at)}`);
 lines.push('STATUS:CONFIRMED','END:VEVENT');
 }lines.push('END:VCALENDAR');return lines.map(fold).join('\r\n')+'\r\n';
}
