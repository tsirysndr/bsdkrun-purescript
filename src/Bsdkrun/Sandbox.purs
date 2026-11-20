module Bsdkrun.Sandbox where

import Prelude
import Bsdkrun.Exec as Exec
import Effect.Aff (Aff)
import Bsdkrun.Internal (Async, toAff)
import Bsdkrun.Types (Sandbox, CreateOptions, ExecOptions, CommandResult, SandboxInfo, Bytes)
import Data.Maybe (Maybe)
import Data.Nullable (Nullable, toMaybe)
import Effect (Effect)

create :: CreateOptions -> Aff (Sandbox)
create opts = toAff (createImpl opts)

foreign import createImpl :: CreateOptions -> Async (Sandbox)

get :: String -> Aff (Sandbox)
get id = toAff (getImpl id)

foreign import getImpl :: String -> Async (Sandbox)

list :: Boolean -> Aff (Array SandboxInfo)
list all = toAff (listImpl all)

foreign import listImpl :: Boolean -> Async (Array SandboxInfo)

execWith :: Array String -> ExecOptions -> Sandbox -> Aff (CommandResult)
execWith command opts box = toAff (execWithImpl command opts box)

foreign import execWithImpl :: Array String -> ExecOptions -> Sandbox -> Async (CommandResult)

statusRaw :: Sandbox -> Aff (Nullable SandboxInfo)
statusRaw box = toAff (statusRawImpl box)

foreign import statusRawImpl :: Sandbox -> Async (Nullable SandboxInfo)

isRunning :: Sandbox -> Aff (Boolean)
isRunning box = toAff (isRunningImpl box)

foreign import isRunningImpl :: Sandbox -> Async (Boolean)

logs :: Boolean -> Sandbox -> Aff (String)
logs boot box = toAff (logsImpl boot box)

foreign import logsImpl :: Boolean -> Sandbox -> Async (String)

-- | Follow the live console (`logs -f`, or the boot log with `true`) on the
-- | current terminal until it ends or the `Aff` is cancelled; yields the exit
-- | status.
followLogs :: Boolean -> Sandbox -> Aff Int
followLogs boot box = toAff (followLogsImpl boot box)

foreign import followLogsImpl :: Boolean -> Sandbox -> Async Int

-- | Stream the machine's console to the current terminal until the `Aff` is
-- | cancelled: what it writes from now on, or everything so far as well with
-- | `true`. Unlike `followLogs`, nothing older is replayed, so a restart
-- | shows its own boot rather than the previous one. Start it before
-- | `start` to catch the boot from its first line.
streamConsole :: Boolean -> Sandbox -> Aff Unit
streamConsole = streamConsoleWith writeStdout

-- | `streamConsole` into a writer instead of the terminal.
streamConsoleWith :: (Bytes -> Effect Unit) -> Boolean -> Sandbox -> Aff Unit
streamConsoleWith write fromStart box = toAff (streamConsoleWithImpl write fromStart box)

foreign import streamConsoleWithImpl :: (Bytes -> Effect Unit) -> Boolean -> Sandbox -> Async Unit
foreign import writeStdout :: Bytes -> Effect Unit

-- | Attach an interactive shell (`bsdkrun shell`) to the machine on the
-- | current terminal; yields its exit status when the session ends.
shell :: Sandbox -> Aff Int
shell box = toAff (shellImpl box)

foreign import shellImpl :: Sandbox -> Async Int

-- | Run a command in the guest with a PTY on the current terminal
-- | (`bsdkrun exec -t`), e.g. `["psql"]`; yields its exit status.
execInteractive :: Array String -> Sandbox -> Aff Int
execInteractive command box = toAff (execInteractiveImpl command box)

foreign import execInteractiveImpl :: Array String -> Sandbox -> Async Int

-- | Run a command in the guest with the current process's stdin, stdout and
-- | stderr bound to it (`bsdkrun exec`), with a PTY when `tty`; yields its
-- | exit status. `execInteractive` is `execAttached true`.
execAttached :: Boolean -> Array String -> Sandbox -> Aff Int
execAttached tty command box = toAff (execAttachedImpl tty command box)

foreign import execAttachedImpl :: Boolean -> Array String -> Sandbox -> Async Int

stop :: Sandbox -> Aff (Sandbox)
stop box = toAff (stopImpl box)

foreign import stopImpl :: Sandbox -> Async (Sandbox)

start :: Sandbox -> Aff (Sandbox)
start box = toAff (startImpl box)

foreign import startImpl :: Sandbox -> Async (Sandbox)

remove :: Boolean -> Sandbox -> Aff (Sandbox)
remove force box = toAff (removeImpl force box)

foreign import removeImpl :: Boolean -> Sandbox -> Async (Sandbox)

update :: Int -> Int -> Sandbox -> Aff (Sandbox)
update cpus mem box = toAff (updateImpl cpus mem box)

foreign import updateImpl :: Int -> Int -> Sandbox -> Async (Sandbox)

connectNetwork :: String -> Sandbox -> Aff (Sandbox)
connectNetwork network box = toAff (connectNetworkImpl network box)

foreign import connectNetworkImpl :: String -> Sandbox -> Async (Sandbox)

disconnectNetwork :: Sandbox -> Aff (Sandbox)
disconnectNetwork box = toAff (disconnectNetworkImpl box)

foreign import disconnectNetworkImpl :: Sandbox -> Async (Sandbox)

foreign import sandboxId :: Sandbox -> String
foreign import setBinaryPath :: String -> Effect Unit
foreign import resolveBinary :: Effect String

exec :: Array String -> Sandbox -> Aff CommandResult
exec command = execWith command Exec.options

status :: Sandbox -> Aff (Maybe SandboxInfo)
status box = toMaybe <$> statusRaw box

sshSetup :: { user :: String, key :: Array String } -> Sandbox -> Aff (CommandResult)
sshSetup opts box = toAff (sshSetupImpl opts box)

foreign import sshSetupImpl :: { user :: String, key :: Array String } -> Sandbox -> Async (CommandResult)

sshAddKey :: Array String -> Sandbox -> Aff (CommandResult)
sshAddKey keys box = toAff (sshAddKeyImpl keys box)

foreign import sshAddKeyImpl :: Array String -> Sandbox -> Async (CommandResult)

sshStatus :: Sandbox -> Aff (CommandResult)
sshStatus box = toAff (sshStatusImpl box)

foreign import sshStatusImpl :: Sandbox -> Async (CommandResult)

tailscaleUp :: { authkey :: String, hostname :: String, args :: Array String } -> Sandbox -> Aff (CommandResult)
tailscaleUp opts box = toAff (tailscaleUpImpl opts box)

foreign import tailscaleUpImpl :: { authkey :: String, hostname :: String, args :: Array String } -> Sandbox -> Async (CommandResult)

tailscaleStatus :: Sandbox -> Aff (CommandResult)
tailscaleStatus box = toAff (tailscaleStatusImpl box)

foreign import tailscaleStatusImpl :: Sandbox -> Async (CommandResult)
