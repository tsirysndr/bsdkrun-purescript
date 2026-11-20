-- | Host TCP ports for `--port HOST:GUEST` forwards. A forward whose host
-- | port is already taken (by another machine, or anything else listening)
-- | makes `create` fail, so probe first, or let `resolve` move each host
-- | port up to the next free one before booting.
module Bsdkrun.Port
  ( isFree
  , isFreeOn
  , findFree
  , resolve
  , hostPorts
  ) where

import Bsdkrun.Internal (Async, toAff)
import Bsdkrun.Types (CreateOptions)
import Effect.Aff (Aff)

-- | Whether nothing listens on the host TCP port.
isFree :: Int -> Aff Boolean
isFree port = toAff (isFreeImpl port)

foreign import isFreeImpl :: Int -> Async Boolean

-- | `isFree` for a forward bound to one address (`"127.0.0.1"`): free when
-- | that address can be bound. A wildcard listener elsewhere does not count,
-- | since the forward wins for its own address; a wildcard bind
-- | (`"0.0.0.0"`) also needs loopback to refuse connections.
isFreeOn :: String -> Int -> Aff Boolean
isFreeOn bind port = toAff (isFreeOnImpl bind port)

foreign import isFreeOnImpl :: String -> Int -> Async Boolean

-- | The first free port at or above the given one, incrementing until one is
-- | found; fails past 65535.
findFree :: Int -> Aff Int
findFree port = toAff (findFreeImpl port)

foreign import findFreeImpl :: Int -> Async Int

-- | Rewrite every `withPorts` forward so its host side is a free port: a taken
-- | port moves up to the next free one (distinct from the other forwards),
-- | the guest side stays. Options without forwards pass through. Read the
-- | outcome with `hostPorts`, or `ports` on `status` once the machine runs.
resolve :: CreateOptions -> Aff CreateOptions
resolve opts = toAff (resolveImpl opts)

foreign import resolveImpl :: CreateOptions -> Async CreateOptions

-- | The host side of each forward, in `withPorts` order.
foreign import hostPorts :: CreateOptions -> Array Int
