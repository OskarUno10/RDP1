import {NextRequest} from "next/server";
import {context,guarded,reply,gh,ApiError} from "@/lib/api";
import {inspect} from "@/lib/setup";
import {runs,active,loadSettings} from "@/lib/workflow";
import {sessionState,type SessionFile,type StatusJob} from "@/lib/session-status";
export async function GET(req:NextRequest){return guarded(async()=>{const c=await context(req);let list;try{list=await runs(c)}catch(e){if(e instanceof ApiError&&e.status===404){const setup=await inspect(c);return reply({repo:c.repo,phase:"setup_required",active:false,run:null,session:null,connection:null,setup,server_time:new Date().toISOString()})}throw e}const run=list.find(active)||list[0]||null;let session:SessionFile|null=null;let sessionReadable=true;
 try{const f=await gh<{content:string}>(c,"/contents/rdp-status.json?ref=status");session=JSON.parse(Buffer.from(f.content,"base64").toString("utf8").replace(/^\uFEFF/,""));}catch(e){if(!(e instanceof ApiError&&e.status===404))sessionReadable=false;}
 let jobs:StatusJob[]=[];let progressAvailable=true;
 if(run){try{jobs=(await gh<{jobs:StatusJob[]}>(c,`/actions/runs/${run.id}/attempts/${run.run_attempt||1}/jobs?per_page=100`)).jobs;}catch{progressAvailable=false;}}
 const state=sessionState(run,session,jobs);const current=state.current;
 return reply({repo:c.repo,username:(await loadSettings(c.repo)).rdp_user,run,active:state.active,session:current?{hostname:session?.hostname,started_at:session?.started_at,expires_at:session?.expires_at,username:session?.rdp_user}:null,connection:state.connection,hardware:current?session?.hardware||null:null,progress:state.progress,progress_available:progressAvailable,session_readable:sessionReadable,games:current?session?.games||null:null,media:current?session?.media||null:null,game_environment:current?session?.game_environment||null:null,server_time:new Date().toISOString(),phase:state.phase});})}
