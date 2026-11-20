import { async } from "../Bsdkrun.Internal/foreign.js";
import * as SDK from "@bsdkrun/sdk";
import { buildCreateArgs } from "../Bsdkrun.Options/foreign.js";

const ID_RE = /^[0-9a-f]{12}$/;
// Mirrors `Sandbox.create` in the runtime, but through our own argv builder so
// `withZfs` reaches the CLI (the runtime's builder does not know `--zfs`).
const createWithZfs = async opts => {
  const res = await SDK.runCli(buildCreateArgs(opts), { logLevel: opts.logLevel ?? 1 });
  if (res.exitCode !== 0) {
    throw new SDK.CommandFailedError(new SDK.CommandResult(res.stdout, res.stderr, res.exitCode, "bsdkrun create"));
  }
  const id = res.stdout.split("\n").map(l => l.trim()).filter(l => ID_RE.test(l)).at(-1);
  if (!id) {
    throw new SDK.CommandFailedError(new SDK.CommandResult(res.stdout, res.stderr, res.exitCode, "bsdkrun create (no machine id in output)"));
  }
  return new SDK.Sandbox(id);
};
export const createImpl = opts => async(signal => (opts.zfs?.length ? createWithZfs(opts) : SDK.Sandbox.create(opts)));

// An interactive child inherits the terminal; the Aff resolves to its exit
// status once it ends, and cancelling the Aff kills it.
const waitChild = (child, signal) => new Promise((resolve, reject) => {
  signal.addEventListener("abort", () => child.kill());
  child.on("error", reject);
  child.on("exit", (code, sig) => resolve(code ?? (sig ? 128 : 1)));
});
export const shellImpl = box => async(signal => waitChild(box.shell(), signal));
export const followLogsImpl = boot => box => async(signal => waitChild(box.followLogs({ boot, stdio: "inherit" }), signal));
export const execInteractiveImpl = command => box => async(signal => waitChild(SDK.spawnCli(["exec", "-t", box.id, ...command], { stdio: "inherit" }), signal));
export const getImpl = id => async(signal => SDK.Sandbox.get(id));
export const listImpl = all => async(signal => SDK.Sandbox.list({all}));
export const execWithImpl = command => opts => box => async(signal => box.exec(command, {...opts, signal}));
export const statusRawImpl = box => async(signal => box.status());
export const isRunningImpl = box => async(signal => box.isRunning());
export const logsImpl = boot => box => async(signal => box.logs({boot}));
export const stopImpl = box => async(signal => Promise.resolve(box.stop()).then(() => box));
export const startImpl = box => async(signal => Promise.resolve(box.start()).then(() => box));
export const removeImpl = force => box => async(signal => Promise.resolve(box.remove({force})).then(() => box));
export const updateImpl = cpus => mem => box => async(signal => Promise.resolve(box.update({cpus, mem})).then(() => box));
export const connectNetworkImpl = network => box => async(signal => Promise.resolve(box.connectNetwork(network)).then(() => box));
export const disconnectNetworkImpl = box => async(signal => Promise.resolve(box.disconnectNetwork()).then(() => box));
export const sandboxId = box => box.id;
export const setBinaryPath = path => () => SDK.setBinaryPath(path);
export const resolveBinary = () => SDK.resolveBinary();

export const sshSetupImpl = opts => box => async(signal => box.ssh.setup(opts));
export const sshAddKeyImpl = keys => box => async(signal => box.ssh.addKey(keys));
export const sshStatusImpl = box => async(signal => box.ssh.status());
export const tailscaleUpImpl = opts => box => async(signal => box.tailscale.up(opts));
export const tailscaleStatusImpl = box => async(signal => box.tailscale.status());
