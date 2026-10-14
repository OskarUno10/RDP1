import {test} from 'node:test';import assert from 'node:assert/strict';
import {stringify} from 'yaml';import {workflowCompatible} from '../src/lib/workflow-contract';import {defaults,choices} from '../src/lib/workflow';
const inputs=Object.fromEntries(Object.keys(defaults).map(k=>[k,choices[k]?{type:'choice',options:choices[k]}:{type:'string'}]));
const source=(v:unknown)=>'# rdpfree-workflow-schema: 5\n'+stringify({on:{workflow_dispatch:{inputs:v}}});
test('workflow compatibility checks actual input names/options, not only marker',()=>{
 assert.equal(workflowCompatible(source(inputs)),true);
 const missing={...inputs};delete missing.microphone;assert.equal(workflowCompatible(source(missing)),false);
 assert.equal(workflowCompatible(source({...inputs,akses:{type:'choice',options:['public']}})),false);
 assert.equal(workflowCompatible(source(inputs).replace('schema: 5','schema: 2')),false);
 assert.equal(workflowCompatible(source({...inputs,new_requirement:{required:true,type:'string'}})),false);
 assert.equal(workflowCompatible('# rdpfree-workflow-schema: 5\nnot yaml ['),false);
});
