import { async } from "../Bsdkrun.Internal/foreign.js";
import * as SDK from "@bsdkrun/sdk";
import { spawn } from "node:child_process";

export const machineName = "bsdkrun-docker";

const cli = async args => {
  const res = await SDK.runCli(args);
  if (res.exitCode !== 0) {
    throw new SDK.CommandFailedError(new SDK.CommandResult(res.stdout, res.stderr, res.exitCode, "bsdkrun " + args.join(" ")));
  }
  return res.stdout;
};
// `--json` output may follow progress lines: the JSON is the last line.
const lastJson = out => JSON.parse(out.trim().split("\n").filter(l => l.trim().startsWith("{") || l.trim().startsWith("[")).at(-1) ?? "null");
const status = s => ({
  running: s.running, machineId: s.machine_id ?? null, machineRunning: s.machine_running, socket: s.socket,
  socketReady: s.socket_ready, apiPort: s.api_port ?? null, version: s.version ?? null, containers: s.containers ?? null,
  images: s.images ?? null, mounts: s.mounts ?? [], context: s.context, contextActive: s.context_active,
  systemSocket: s.system_socket, disk: s.disk ?? null, diskSize: s.disk_size ?? null,
});

export const statusImpl = async(signal => cli(["docker", "status", "--json"]).then(out => status(lastJson(out))));
export const startImpl = opts => async(signal => cli([
  "docker", "start", "--json", "--cpus", String(opts.cpus), "--mem", String(opts.mem),
  ...(opts.publishBind === null || opts.publishBind === undefined ? [] : ["--publish-bind", opts.publishBind]),
]).then(out => status(lastJson(out))));
export const stopImpl = async(signal => cli(["docker", "stop"]).then(() => {}));
export const containersImpl = all => async(signal => cli(["docker", "ps", "--json", ...(all ? ["--all"] : [])]).then(out => lastJson(out) ?? []));

// The host's own `docker` CLI, pointed at the engine's socket.
let socketCache;
const engineEnv = async () => {
  socketCache ??= (await cli(["docker", "status", "--json"]).then(out => lastJson(out).socket));
  return { ...process.env, DOCKER_HOST: "unix://" + socketCache };
};
const missing = e => e.code === "ENOENT" ? new Error("the `docker` CLI is not installed on this host (brew install docker)") : e;
export const dockerImpl = args => async(async signal => {
  const env = await engineEnv();
  return new Promise((resolve, reject) => {
    const child = spawn("docker", args, { env, stdio: ["ignore", "pipe", "pipe"], signal });
    const out = [], err = [];
    child.stdout.on("data", d => out.push(d));
    child.stderr.on("data", d => err.push(d));
    child.on("error", e => reject(missing(e)));
    child.on("close", code => resolve({ stdout: Buffer.concat(out).toString("utf8"), stderr: Buffer.concat(err).toString("utf8"), exitCode: code ?? 1 }));
  });
});
export const dockerAttachedImpl = args => async(async signal => {
  const env = await engineEnv();
  return new Promise((resolve, reject) => {
    const child = spawn("docker", args, { env, stdio: "inherit" });
    signal.addEventListener("abort", () => child.kill());
    child.on("error", e => reject(missing(e)));
    child.on("exit", (code, sig) => resolve(code ?? (sig ? 128 : 1)));
  });
});
