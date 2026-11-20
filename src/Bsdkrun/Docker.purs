-- | The shared Docker engine (`bsdkrun docker`): one microVM named
-- | `bsdkrun-docker` running dockerd, its API served on a host socket that
-- | the host's own `docker` CLI drives. Containers' published ports are
-- | mirrored onto the host by bsdkrun. The engine is a machine like any
-- | other, so `Bsdkrun.Zfs` can attach volumes to it (stopped, for a new
-- | volume; live, for another branch of one it holds).
module Bsdkrun.Docker
  ( machineName
  , status
  , start
  , stop
  , containers
  , docker
  , dockerAttached
  ) where

import Prelude
import Bsdkrun.Internal (Async, toAff)
import Bsdkrun.Types (CommandResult, DockerContainer, DockerStatus)
import Data.Maybe (Maybe)
import Data.Nullable (Nullable, toNullable)
import Effect.Aff (Aff)

-- | The engine VM's machine name, for `Bsdkrun.Zfs` and `Bsdkrun.Sandbox`.
foreign import machineName :: String

-- | Whether the engine runs, how to reach it, and what it holds.
status :: Aff DockerStatus
status = toAff statusImpl

foreign import statusImpl :: Async DockerStatus

-- | Start the engine, creating its VM with these resources the first time
-- | (`bsdkrun docker start`); resumes an existing one as it is. `publishBind`
-- | is where published container ports bind on the host: `"127.0.0.1"`, or
-- | `Nothing` for bsdkrun's default, `mirror` (what the container asked for).
-- | Inside the VM a port must be published on every interface to be
-- | reachable from the host at all: `-p 5432:5432`, not `-p 127.0.0.1:...`.
start :: { cpus :: Int, mem :: Int, publishBind :: Maybe String } -> Aff DockerStatus
start opts = toAff (startImpl { cpus: opts.cpus, mem: opts.mem, publishBind: toNullable opts.publishBind })

foreign import startImpl :: { cpus :: Int, mem :: Int, publishBind :: Nullable String } -> Async DockerStatus

-- | Stop the engine VM; images and containers stay on its disk.
stop :: Aff Unit
stop = toAff stopImpl

foreign import stopImpl :: Async Unit

-- | The engine's containers (`true` includes stopped ones).
containers :: Boolean -> Aff (Array DockerContainer)
containers all = toAff (containersImpl all)

foreign import containersImpl :: Boolean -> Async (Array DockerContainer)

-- | Run the host's `docker` CLI against the engine and capture its output;
-- | a non-zero exit is data, not an error.
docker :: Array String -> Aff CommandResult
docker args = toAff (dockerImpl args)

foreign import dockerImpl :: Array String -> Async CommandResult

-- | Run the host's `docker` CLI against the engine with the current
-- | terminal's stdin, stdout and stderr (`exec -it`, `logs -f`); yields its
-- | exit status, and cancelling the `Aff` kills it.
dockerAttached :: Array String -> Aff Int
dockerAttached args = toAff (dockerAttachedImpl args)

foreign import dockerAttachedImpl :: Array String -> Async Int
