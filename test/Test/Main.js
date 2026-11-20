import { mkdtempSync, writeFileSync, rmSync, readFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { createServer } from "node:net";
import { setBinaryPath, resetPreflight } from "@bsdkrun/sdk";
import { async } from "../Bsdkrun.Internal/foreign.js";

export const setup = () => {
  const dir = mkdtempSync(join(tmpdir(), "bsdkrun-purs-test-"));
  const bin = join(dir, "bsdkrun");
  const previous = process.env.BSDKRUN_NO_AUTO_INSTALL;
  process.env.BSDKRUN_NO_AUTO_INSTALL = "1";
  resetPreflight();
  writeFileSync(bin, `#!/usr/bin/env node
import {spawn} from 'node:child_process';
import {writeFileSync,readFileSync} from 'node:fs';
const args=process.argv.slice(4);
writeFileSync(${JSON.stringify(join(dir, 'args'))}, JSON.stringify(args));
const op=args.shift();
if (op==='linux') console.log('abcdef123456');
else if(op==='ps') console.log(JSON.stringify([{id:'abcdef123456',name:'test',kind:'linux',running:true,ports:[],cpus:1,mem:512}]));
else if(op==='exec') {
  while(args[0]==='-e') args.splice(0,2);
  args.shift();
  const child=spawn(args.shift(),args,{stdio:'inherit'});
  child.on('error',e=>{console.error(e.message);process.exitCode=127;});
  child.on('exit',code=>process.exitCode=code);
} else if(op==='cp') {
  if(args[0]==='-') writeFileSync(${JSON.stringify(join(dir, 'payload'))},readFileSync(0));
  else process.stdout.write(readFileSync(${JSON.stringify(join(dir, 'payload'))}));
} else if(op==='cache') console.log(JSON.stringify({restored:false,requested_key:'miss'}));
else if(op==='zfs') console.log(args[0]==='ls'?JSON.stringify([{name:'data',path:'/x/data.img',size_bytes:1,branches:[{name:'main',origin:null,created_at:1}],attached_to:[{machine:'abcdef123456',machine_name:'test',running:true,mounts:[{branch:'main',mountpoint:'/mnt/data'}]}]}]):'data@'+args[2]);
else if(op==='--version') console.log('bsdkrun 0.0.0-test');
`, {mode: 0o755});
  setBinaryPath(bin);
  return {
    args: () => JSON.parse(readFileSync(join(dir, "args"), "utf8")),
    cleanup: () => {
      rmSync(dir, {recursive: true, force: true});
      if(previous === undefined) delete process.env.BSDKRUN_NO_AUTO_INSTALL;
      else process.env.BSDKRUN_NO_AUTO_INSTALL = previous;
      setBinaryPath(undefined);
      resetPreflight();
    },
  };
};
// Hold a random free port open so port probes have something to collide with.
export const occupyPortImpl = async(signal => new Promise((resolve, reject) => {
  const server = createServer();
  server.once("error", reject);
  server.listen({ host: "0.0.0.0", port: 0 }, () => resolve({ port: server.address().port, close: () => server.close() }));
}));
export const makeSink = () => {
  const chunks = [];
  return {
    write: bytes => () => { chunks.push(Buffer.from(bytes)); },
    read: () => Buffer.concat(chunks),
  };
};
// Stub the HTTP boundary to inspect the real runtime's GraphQL encoding.
export const mockDaemon = () => {
  const original = globalThis.fetch;
  const requests = [];
  globalThis.fetch = async (_url, opts) => {
    const request = JSON.parse(opts.body);
    requests.push(request);
    const data = request.query.includes('runLinux') ? {runLinux:'remote-id'}
      : request.query.includes('removeMachines') ? {removeMachines:{exitCode:0,stdout:'',stderr:''}}
      : {machines:[]};
    return new Response(JSON.stringify({data}), {status:200});
  };
  return {
    input: () => JSON.stringify(requests.at(-1).variables),
    linuxInput: () => {
      const i = requests.at(-1).variables.i;
      return {image:i.image, name:i.net.name, network:i.net.network, noNet:i.net.noNet, env:i.env,
        valid: !('os' in i) && !('name' in i) && !('disabled' in i.net)};
    },
    cleanup: () => { globalThis.fetch = original; },
  };
};
