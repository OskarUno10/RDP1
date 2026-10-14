import {ApiError,Context,gh} from "./api";
import {db} from "./db";
export const choices:Record<string,string[]>={durasi_menit:["15","30","60","120","180","240","300","330","360"],akses:["tailscale","portmap"],runner:["windows-2022","windows-2025","windows-latest"],microphone:["ya","tidak"],roblox:["ya","tidak"],minecraft_java:["ya","tidak"],minecraft_bedrock:["ya","tidak"],storage_boost:["ya","tidak"],debloat:["ringan","full","tidak"],samp:["ya","tidak"],win10:["ya","tidak"],xydesk:["ya","tidak"],ekstra:["ya","tidak"],grafis:["software","tidak"]};
export const defaults:Record<string,string>={durasi_menit:"360",hostname:"rdpfree",rdp_user:"xyadmin",akses:"tailscale",portmap_host:"",portmap_port:"",runner:"windows-2022",microphone:"ya",roblox:"tidak",minecraft_java:"tidak",minecraft_bedrock:"tidak",storage_boost:"tidak",debloat:"ringan",samp:"ya",win10:"tidak",xydesk:"ya",ekstra:"tidak",grafis:"tidak"};
export function validate(raw:Record<string,unknown>){const inputs={...defaults};for(const [k,v] of Object.entries(raw)){if(["wallpaper","wallpaper_url","gta_sa_url","samp_extra"].includes(k))continue;if(!Object.prototype.hasOwnProperty.call(defaults,k)||typeof v!=="string")throw new ApiError(400,"Parameter tidak dikenal: "+k);inputs[k]=v;}
 for(const [k,allowed] of Object.entries(choices))if(!allowed.includes(inputs[k]))throw new ApiError(400,"Pilihan tidak valid: "+k);
 if(!/^[a-zA-Z0-9][a-zA-Z0-9-]{0,29}$/.test(inputs.hostname))throw new ApiError(400,"Hostname harus 1–30 huruf, angka, atau tanda minus");
 if(!/^[a-zA-Z][a-zA-Z0-9_-]{2,19}$/.test(inputs.rdp_user)||/^(administrator|guest|defaultaccount|wdagutilityaccount|system|localservice|networkservice|con|prn|aux|nul)$/i.test(inputs.rdp_user))throw new ApiError(400,"Username RDP tidak valid");
 if(inputs.portmap_host&&!/^(?=.{1,253}$)(?:[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]{2,63}$/.test(inputs.portmap_host))throw new ApiError(400,"Hostname Portmap tidak valid; jangan sertakan tcp:// atau port");
 if(inputs.portmap_port&&(!/^\d{1,5}$/.test(inputs.portmap_port)||Number(inputs.portmap_port)<1||Number(inputs.portmap_port)>65535))throw new ApiError(400,"Port publik harus 1–65535");
 for(const k of ["gta_sa_url"]){if(inputs[k]){try{const u=new URL(inputs[k]);if(u.protocol!=="https:"||u.username||u.password||inputs[k].length>2000)throw Error();}catch{throw new ApiError(400,k+" harus URL HTTPS")}}}return inputs;}
export function migrateSettings(raw:Record<string,unknown>){
 const migrated={...raw};delete migrated.tunnel_provider;delete migrated.wallpaper;delete migrated.wallpaper_url;if(migrated.akses!=="portmap")migrated.akses="tailscale";
 // Legacy labels are migrated to the real default image; no workflow starts on save.
 delete migrated.gta_sa_url;delete migrated.samp_extra;
 if(!("runner" in migrated)||["github","self-hosted"].includes(String(migrated.runner)))migrated.runner="windows-2022";
 return validate(migrated);
}
export async function loadSettings(repo:string){const r=await db().prepare("SELECT inputs FROM settings WHERE repo=?").bind(repo).first<{inputs:string}>();return r?migrateSettings(JSON.parse(r.inputs)):{...defaults};}
export type Run={id:number;run_attempt?:number;status:string;conclusion:string|null;created_at:string;run_started_at:string;html_url:string;name:string;workflow_id:number};
export async function runs(ctx:Context){return (await gh<{workflow_runs:Run[]}>(ctx,"/actions/workflows/rdp-6h.yml/runs?per_page=30")).workflow_runs;}
export const active=(r:Run)=>["queued","in_progress","waiting","requested","pending"].includes(r.status);
