import { async } from "../Bsdkrun.Internal/foreign.js";
import { createServer, connect } from "node:net";

const MAX_PORT = 65535;

// A port is free on an address when a listener can bind it. For a wildcard
// bind that is not enough: BSD's SO_REUSEADDR (which Node always sets) lets
// it coexist with a loopback listener that would then take the loopback
// traffic, so loopback must also refuse connections. A specific address is
// only asked to bind: a wildcard listener elsewhere (Docker's dual-stack
// `*:port`, say) does not stop a 127.0.0.1 forward, which wins for its
// address.
const WILDCARDS = new Set(["0.0.0.0", "::", ""]);
const canListen = (bind, port) => new Promise(resolve => {
  const server = createServer();
  server.unref();
  server.once("error", () => resolve(false));
  server.listen({ host: bind, port, exclusive: true }, () => server.close(() => resolve(true)));
});
const refusesConnections = port => new Promise(resolve => {
  const socket = connect({ host: "127.0.0.1", port });
  socket.unref();
  socket.setTimeout(500);
  socket.once("connect", () => { socket.destroy(); resolve(false); });
  socket.once("timeout", () => { socket.destroy(); resolve(true); });
  socket.once("error", () => resolve(true));
});
const isFreeOn = async (bind, port) => Number.isInteger(port) && port > 0 && port <= MAX_PORT
  && (await canListen(bind, port)) && (!WILDCARDS.has(bind) || await refusesConnections(port));
const isFree = port => isFreeOn("0.0.0.0", port);

// Walk upwards from `start` until a port is free and not in `taken`.
const findFree = async (start, taken = new Set()) => {
  for (let port = Math.max(1, start); port <= MAX_PORT; port++) {
    if (!taken.has(port) && await isFree(port)) return port;
  }
  throw new Error(`No free TCP port between ${start} and ${MAX_PORT}`);
};

export const isFreeImpl = port => async(signal => isFree(port));
export const isFreeOnImpl = bind => port => async(signal => isFreeOn(bind, port));
export const findFreeImpl = port => async(signal => findFree(port));

// A forward is `HOST:GUEST`, optionally prefixed by a bind address, or a
// `{host, guest}` object. Only the host side moves.
const FORWARD = /^(.*?)(\d{1,5}):(\d{1,5})$/;
const hostPort = entry => {
  if (typeof entry === "string") {
    const m = FORWARD.exec(entry);
    return m ? Number(m[2]) : undefined;
  }
  return typeof entry?.host === "number" ? entry.host : undefined;
};
const withHostPort = (entry, port) => typeof entry === "string"
  ? entry.replace(FORWARD, (_, prefix, _host, guest) => `${prefix}${port}:${guest}`)
  : { ...entry, host: port };

export const hostPorts = opts => (opts.net?.ports ?? []).map(hostPort).filter(p => p !== undefined);

export const resolveImpl = opts => async(async signal => {
  const ports = opts.net?.ports ?? [];
  if (ports.length === 0) return opts;
  const taken = new Set();
  const resolved = [];
  for (const entry of ports) {
    const wanted = hostPort(entry);
    if (wanted === undefined) { resolved.push(entry); continue; }
    const port = await findFree(wanted, taken);
    taken.add(port);
    resolved.push(withHostPort(entry, port));
  }
  return { ...opts, net: { ...opts.net, ports: resolved } };
});
