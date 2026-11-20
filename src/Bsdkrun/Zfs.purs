-- | ZFS volumes (`bsdkrun zfs`): one zpool per volume on a sparse disk image,
-- | with branches forked copy-on-write inside the guest (`zfs snapshot` +
-- | `zfs clone`). A pool is imported by one machine at a time: attach to a
-- | stopped machine and `start` it, or attach another branch live to the
-- | machine that already holds the pool. Targets are `VOL` or `VOL@BRANCH`.
module Bsdkrun.Zfs
  ( list
  , branches
  , create
  , branch
  , attach
  , attachAt
  , detach
  , destroy
  , target
  ) where

import Prelude
import Bsdkrun.Internal (Async, toAff)
import Bsdkrun.Types (ZfsBranchInfo, ZfsVolumeInfo)
import Data.Maybe (Maybe(..), maybe)
import Data.Nullable (Nullable, toNullable)
import Effect.Aff (Aff)

-- | Every volume, with its branches and holder.
list :: Aff (Array ZfsVolumeInfo)
list = toAff listImpl

foreign import listImpl :: Async (Array ZfsVolumeInfo)

-- | The branches of one volume.
branches :: String -> Aff (Array ZfsBranchInfo)
branches volume = toAff (branchesImpl volume)

foreign import branchesImpl :: String -> Async (Array ZfsBranchInfo)

-- | Create a volume of the given size (`"10G"`, `"512M"`; sparse, so it costs
-- | nothing until written). The pool and its `main` branch are made the first
-- | time a guest imports it. Returns the CLI's report.
create :: String -> Maybe String -> Aff String
create name size = toAff (createImpl name (toNullable size))

foreign import createImpl :: String -> Nullable String -> Async String

-- | Fork `volume`'s branch `from` (`main` when `Nothing`) into a new branch.
-- | Runs in the machine holding the volume, or in a short-lived FreeBSD helper
-- | when no machine does, so it can take as long as a BSD boot. Returns the
-- | new `VOL@BRANCH`.
branch :: String -> String -> Maybe String -> Aff String
branch volume name from = toAff (branchImpl volume name (toNullable from))

foreign import branchImpl :: String -> String -> Nullable String -> Async String

-- | Attach `VOL` or `VOL@BRANCH` to a machine at the default mountpoint
-- | (`/mnt/VOL`, or `/mnt/VOL-BRANCH` for a branch other than `main`).
attach :: String -> String -> Aff String
attach t machine = attachAt t machine Nothing

-- | Attach `VOL` or `VOL@BRANCH` to a machine, mounting it at the given guest
-- | path. A stopped machine picks it up on `start`; the running holder of the
-- | pool mounts it live; any other running machine is refused.
attachAt :: String -> String -> Maybe String -> Aff String
attachAt t machine mount = toAff (attachImpl t machine (toNullable mount))

foreign import attachImpl :: String -> String -> Nullable String -> Async String

-- | Detach one branch (`VOL@BRANCH`) or the whole volume (`VOL`) from a
-- | machine. Live for a running machine; the disk leaves on next start.
detach :: String -> String -> Aff String
detach t machine = toAff (detachImpl t machine)

foreign import detachImpl :: String -> String -> Async String

-- | Destroy branches (`VOL@BRANCH`) or whole volumes (`VOL`) with their
-- | images. `force` destroys a volume still attached to a stopped machine.
destroy :: Array String -> Boolean -> Aff Unit
destroy targets force = toAff (destroyImpl targets force)

foreign import destroyImpl :: Array String -> Boolean -> Async Unit

-- | `VOL@BRANCH`, or just `VOL` for `main` when the branch is `Nothing`.
target :: String -> Maybe String -> String
target volume = maybe volume \b -> volume <> "@" <> b
