import {createClient} from 'npm:@supabase/supabase-js@2.57.4';
import {subscriptionCalendar} from './calendar.js';
const admin=createClient(Deno.env.get('SUPABASE_URL')!,Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,{auth:{persistSession:false,autoRefreshToken:false}});
const headers={'Access-Control-Allow-Origin':'https://plania-liard.vercel.app','Access-Control-Allow-Headers':'authorization,x-client-info,apikey,content-type','Cache-Control':'private, no-store','Referrer-Policy':'no-referrer','X-Content-Type-Options':'nosniff'};
const json=(value:unknown,status=200)=>new Response(JSON.stringify(value),{status,headers:{...headers,'Content-Type':'application/json'}});
const hash=async(s:string)=>Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',new TextEncoder().encode(s))),b=>b.toString(16).padStart(2,'0')).join('');
async function rpc(op:string,uid:string|null,payload:unknown={}){const {data,error}=await admin.rpc('plania_calendar',{op,uid,payload});if(error)throw error;return data}
Deno.serve(async(req:Request)=>{try{
 if(req.method==='OPTIONS')return new Response('ok',{headers});
 if(req.method==='GET'||req.method==='HEAD'){
  const match=new URL(req.url).pathname.match(/\/([a-f0-9]{64})\/plania\.ics$/);
  if(!match)return json({error:'Calendario no disponible'},404);
  const data=await rpc('feed',null,{hash:await hash(match[1])});
  if(!data)return json({error:'Calendario no disponible'},404);
  return new Response(req.method==='HEAD'?null:subscriptionCalendar(data.events,data.timezone),{headers:{...headers,'Content-Type':'text/calendar; charset=utf-8','Content-Disposition':'inline; filename="PlanIA.ics"'}});
 }
 if(req.method!=='POST')return json({error:'Método no permitido'},405);
 const bearer=req.headers.get('authorization')?.replace(/^Bearer /i,'');
 if(!bearer)return json({error:'Inicia sesión'},401);
 const {data:{user},error}=await admin.auth.getUser(bearer);if(error||!user)return json({error:'Sesión no válida'},401);
 const claims=JSON.parse(new TextDecoder().decode(Uint8Array.from(atob(bearer.split('.')[1].replace(/-/g,'+').replace(/_/g,'/')),c=>c.charCodeAt(0))));
 const session=await admin.rpc('plania_service',{op:'session-check',uid:user.id,payload:{session_id:claims.session_id}});
 if(session.error||!session.data?.valid)return json({error:'Vuelve a iniciar sesión'},401);
 const {data:factors}=await admin.auth.admin.mfa.listFactors({userId:user.id});
 if(factors?.factors?.some(f=>f.status==='verified')&&claims.aal!=='aal2')return json({error:'Completa la verificación en dos pasos'},403);
 const body=await req.json();
 if(body.action==='status'||body.action==='revoke')return json(await rpc(body.action,user.id));
 if(body.action==='create'){
  if(!Array.isArray(body.category_ids)||body.category_ids.length>500)return json({error:'Revisa las tipologías'},400);
  const token=Array.from(crypto.getRandomValues(new Uint8Array(32)),b=>b.toString(16).padStart(2,'0')).join('');
  await rpc('create',user.id,{hash:await hash(token),category_ids:body.category_ids});
  return json({url:`${Deno.env.get('SUPABASE_URL')}/functions/v1/plania-calendar/${token}/plania.ics`});
 }
 return json({error:'Acción no válida'},400);
 }catch{return json({error:'No se pudo completar la operación. Revisa tu sesión y las tipologías.'},400)}});
