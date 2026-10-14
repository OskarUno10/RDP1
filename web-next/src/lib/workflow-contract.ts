import {parse} from "yaml";
import {defaults,choices} from "./workflow";
export function workflowCompatible(source:string):boolean {
 if(source.length>1_000_000||!/^# rdpfree-workflow-schema: 5\s*$/m.test(source))return false;
 try {
  const doc=parse(source,{maxAliasCount:20});
  const inputs=doc?.on?.workflow_dispatch?.inputs;
  if(!inputs||typeof inputs!=="object")return false;
  for(const key of Object.keys(defaults)){
   if(!Object.prototype.hasOwnProperty.call(inputs,key))return false;
   const spec=inputs[key];
   if(choices[key]){if(spec?.type!=="choice"||!Array.isArray(spec.options)||!choices[key].every(v=>spec.options.includes(v)))return false;}
   else if(spec?.type!=="string")return false;
  }
  return !Object.entries(inputs).some(([key,spec])=>!Object.prototype.hasOwnProperty.call(defaults,key)&&!!(spec as {required?:boolean})?.required);
 }catch{return false;}
}
