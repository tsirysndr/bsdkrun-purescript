module Bsdkrun.Types where

import Data.Nullable (Nullable)

foreign import data Sandbox :: Type
foreign import data Client :: Type
-- | Byte-exact Uint8Array, including Node Buffers. Never decoded implicitly.
foreign import data Bytes :: Type
foreign import data CreateOptions :: Type
foreign import data ExecOptions :: Type

type CommandResult = { stdout :: String, stderr :: String, exitCode :: Int }
type RemoteResult = { output :: Bytes, exitCode :: Int }
type PortForward = { bind :: String, host :: Int, guest :: Int }
type SandboxInfo =
  { id :: String
  , name :: Nullable String
  , image :: String
  , kind :: String
  , command :: String
  , status :: String
  , running :: Boolean
  , exitCode :: Nullable Int
  , pid :: Nullable Int
  , detached :: Boolean
  , cpus :: Int
  , mem :: Int
  , volume :: Nullable String
  , stateDir :: String
  , network :: Nullable String
  , netIp :: Nullable String
  , ports :: Array PortForward
  , createdAt :: Number
  , finishedAt :: Nullable Number
  }

type ImageInfo = { id :: String, reference :: String, digest :: String, size :: Number, rootfs :: String, createdAt :: Number }
type VolumeInfo = { name :: String, guest :: Nullable String, base :: Nullable String, path :: String, size :: String, createdAt :: Nullable Number, tracked :: Boolean }
type NetworkInfo = { name :: String, subnet :: String, gateway :: String, members :: Int, running :: Int, up :: Boolean, createdAt :: Nullable Number }
type CacheEntry = { key :: String, path :: String, compression :: String, size :: Number, created :: Number, digest :: String }
type RestoreResult = { restored :: Boolean, requestedKey :: String, key :: Nullable String, path :: Nullable String, size :: Nullable Number, compression :: Nullable String, created :: Nullable Number }

-- | One branch of a ZFS volume mounted in a guest.
type ZfsMountInfo = { branch :: String, mountpoint :: String }
-- | A branch of a ZFS volume: a dataset cloned copy-on-write inside its pool.
-- | `origin` is the branch it was cloned from; `null` for `main`.
type ZfsBranchInfo = { name :: String, origin :: Nullable String, createdAt :: Nullable Number }
-- | The machine holding a ZFS volume and what it mounts.
type ZfsAttachmentInfo = { machine :: String, machineName :: Nullable String, running :: Boolean, mounts :: Array ZfsMountInfo }
-- | A ZFS volume as reported by `bsdkrun zfs ls --json`. `attachedTo` holds
-- | the holder, if any; at most one.
type ZfsVolumeInfo =
  { name :: String
  , path :: String
  , sizeBytes :: Number
  , size :: Nullable String
  , branches :: Array ZfsBranchInfo
  , attachedTo :: Array ZfsAttachmentInfo
  , createdAt :: Nullable Number
  }

-- | `bsdkrun docker status --json`: `running` means the VM is up and dockerd
-- | answered; `machineId` is null until the engine VM has been created.
type DockerStatus =
  { running :: Boolean
  , machineId :: Nullable String
  , machineRunning :: Boolean
  , socket :: String
  , socketReady :: Boolean
  , apiPort :: Nullable Int
  , version :: Nullable String
  , containers :: Nullable Int
  , images :: Nullable Int
  , mounts :: Array String
  , context :: Boolean
  , contextActive :: Boolean
  , systemSocket :: Boolean
  , disk :: Nullable String
  , diskSize :: Nullable Number
  }
-- | A container as `bsdkrun docker ps --json` reports it; `ports` are the
-- | published forwards bsdkrun mirrors onto the host, each `HOST:GUEST/proto`.
type DockerContainer = { id :: String, name :: String, image :: String, command :: String, state :: String, status :: String, ports :: Array String, created :: Number }
