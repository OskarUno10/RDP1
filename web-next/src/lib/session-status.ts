// Workflow status is authoritative; a leftover status branch must never revive a stopped run.
export type SessionFile={run_id?:string;run_attempt?:string;active?:boolean;started_at?:string;expires_at?:string;rdp_user?:string;hostname?:string;hardware?:{cpu_threads?:number;ram_gb?:number;disk_free_gb?:number};games?:Record<string,unknown>;media?:Record<string,unknown>;game_environment?:Record<string,unknown>;akses?:{mode?:string;portmap?:{host?:string;port?:number;status?:string};tailscale?:{ip?:string;status?:string;note?:string}}};
export type StatusRun={id:number;status:string;conclusion:string|null;run_attempt?:number};
export type JobStep={name:string;status:string;conclusion:string|null;number:number};
export type StatusJob={id:number;name:string;status:string;conclusion:string|null;steps?:JobStep[]};
const pending=["queued","waiting","requested","pending"];
export function sessionState(run:StatusRun|null,session:SessionFile|null,jobs:StatusJob[]=[],now=Date.now()){
 const running=run?.status==="in_progress",active=!!run&&(running||pending.includes(run.status));
 const matching=!!run&&String(session?.run_id)===String(run.id)&&(Number(session?.run_attempt||1)===Number(run.run_attempt||1));
 const steps=jobs.flatMap(j=>j.steps||[]).map(s=>({name:s.name,status:s.status,conclusion:s.conclusion,number:s.number}));
 const failure=steps.find(s=>s.conclusion==="failure"||s.conclusion==="timed_out")||null;
 const optionalFailure=failure&&/^(Verifikasi dependensi|Setup grafis|Setup tampilan|Storage boost)/.test(failure.name);
 const current=!!(running&&matching&&session?.active&&Date.parse(session.expires_at||"")>now&&(!failure||optionalFailure));
 const ts=current?session?.akses?.tailscale:null;
 // Restrict the advertised RDP endpoint to a valid Tailscale IPv4 address.
 const parts=ts?.ip?.split(".").map(Number)||[];
 const validIP=parts.length===4&&parts.every(n=>Number.isInteger(n)&&n>=0&&n<=255)&&parts[0]===100&&parts[1]>=64&&parts[1]<=127;
 const pm=current&&session?.akses?.mode==="portmap"?session.akses.portmap:null;
 const publicReady=pm?.status==="ok"&&typeof pm.host==="string"&&/^(?=.{1,253}$)(?:[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]{2,63}$/.test(pm.host)&&Number.isInteger(pm.port)&&Number(pm.port)>0&&Number(pm.port)<=65535;
 const host=publicReady?pm.host:ts?.status==="ok"&&validIP?ts.ip:null;
 const phase=run?.status==="completed"?(run.conclusion==="success"?"stopped":run.conclusion==="cancelled"?"cancelled":"failed"):failure&&!optionalFailure?"failed":pending.includes(run?.status||"")?"queued":current&&host?"ready":active?"preparing":"stopped";
 return {active,current,phase,connection:host?{host,port:publicReady?Number(pm?.port):3389,username:session?.rdp_user||"xyadmin",password_required:true,transport:publicReady?"portmap":"tailscale"}:null,progress:{current_step:steps.find(s=>s.status==="in_progress")?.name||null,failed_step:failure?.name||null,completed:steps.filter(s=>s.status==="completed").length,total:steps.length,steps}};
}
