module Test.Main where

import Prelude
import Bsdkrun as B
import Bsdkrun.Cache as Cache
import Bsdkrun.CI as CI
import Bsdkrun.Client as Client
import Bsdkrun.Error as Error
import Bsdkrun.Exec as Exec
import Bsdkrun.Options as Options
import Bsdkrun.Types (Bytes)
import Data.Either (Either(..))
import Data.Maybe (Maybe(..))
import Data.Nullable (null, toMaybe)
import Effect (Effect)
import Effect.Aff (Aff, attempt, bracket, delay, forkAff, killFiber, launchAff_, throwError)
import Effect.Class (liftEffect)
import Effect.Console (log)
import Effect.Exception (error)
import Foreign.Object as Object
import Bsdkrun.FileSystem as FS
import Bsdkrun.Host as Host
import Bsdkrun.Internal (Async, toAff)
import Bsdkrun.Docker as Docker
import Bsdkrun.Port as Port
import Bsdkrun.Sandbox as Sandbox
import Data.Time.Duration (Milliseconds(..))
import Bsdkrun.Zfs as Zfs
import Data.Array as Array
import Data.String as String

foreign import setup :: Effect { args :: Effect (Array String), console :: String -> Effect Unit, cleanup :: Effect Unit }
foreign import occupyPortImpl :: String -> Async { port :: Int, close :: Effect Unit }
foreign import makeSink :: Effect { write :: Bytes -> Effect Unit, read :: Effect Bytes }
foreign import mockDaemon :: Effect { input :: Effect String, linuxInput :: Effect { image :: String, name :: String, network :: String, noNet :: Boolean, env :: Array String, valid :: Boolean }, cleanup :: Effect Unit }

assert :: String -> Boolean -> Aff Unit
assert message ok = unless ok $ throwError $ error message

main :: Effect Unit
main = launchAff_ do
  assert "text preserves significant spaces" (Exec.text { stdout: "  value \n\n", stderr: "", exitCode: 0 } == "  value ")
  let base = Options.linux "alpine"
  let
    opts = base # Options.withName "web" # Options.withCpus 2
      # Options.withNetwork "devnet"
      # Options.withPorts [ "8080:80" ]
      # Options.withEnv (Object.singleton "A" "$(touch unsafe); spaced")
      # Options.withCommand [ "printf", "%s", "hello world" ]
  assert "immutable options" (Options.buildCreateArgs base == [ "linux", "alpine", "-d" ])
  assert "structured create arguments"
    ( Options.buildCreateArgs opts ==
        [ "linux", "alpine", "-d", "-e", "A=$(touch unsafe); spaced", "--port", "8080:80", "--network", "devnet", "--name", "web", "--cpus", "2", "--", "printf", "%s", "hello world" ]
    )
  assert "BSD options" ((Options.freebsd # Options.withVersion "15.0" # Options.withPersist true # Options.buildCreateArgs) == [ "freebsd", "-d", "--version", "15.0", "--persist" ])
  assert "firmware" (Options.buildCreateArgs (Options.firmware "uefi" "disk") == [ "firmware", "--firmware", "uefi", "--disk", "disk", "-d" ])
  assert "kernel" (Options.buildCreateArgs (Options.kernel "vmlinuz") == [ "kernel", "--kernel", "vmlinuz", "-d" ])
  assert "NetBSD" (Options.buildCreateArgs Options.netbsd == [ "netbsd", "-d" ])
  assert "Nanos" (Options.buildCreateArgs (Options.nanos "disk") == [ "nanos", "-d", "disk" ])
  assert "Unikraft" (Options.buildCreateArgs (Options.unikraft ".") == [ "unikraft", "-d", "." ])
  assert "Solo5" (Options.buildCreateArgs (Options.solo5 ".") == [ "solo5", "-d", "." ])
  assert "OSv" (Options.buildCreateArgs (Options.osv "loader") == [ "osv", "-d", "loader" ])
  assert "zfs flags precede the guest command"
    ( (Options.linux "postgres" # Options.withZfs [ "data@main:/var/lib/postgresql" ] # Options.withCommand [ "postgres" ] # Options.buildCreateArgs) ==
        [ "linux", "postgres", "-d", "--zfs", "data@main:/var/lib/postgresql", "--", "postgres" ]
    )
  assert "zfs flags on BSD" ((Options.freebsd # Options.withZfs [ "data", "data@dev:/srv" ] # Options.buildCreateArgs) == [ "freebsd", "-d", "--zfs", "data", "--zfs", "data@dev:/srv" ])
  assert "zfs ignored where unsupported" (Options.buildCreateArgs (Options.nanos "disk" # Options.withZfs [ "data" ]) == [ "nanos", "-d", "disk" ])
  assert "disk size grows BSD root disks" ((Options.freebsd # Options.withZfs [ "data" ] # Options.withDiskSize "8G" # Options.buildCreateArgs) == [ "freebsd", "-d", "--zfs", "data", "--disk-size", "8G" ])
  assert "disk size ignored on Linux" ((Options.linux "alpine" # Options.withDiskSize "8G" # Options.buildCreateArgs) == [ "linux", "alpine", "-d" ])
  assert "zfs target" (Zfs.target "data" Nothing == "data" && Zfs.target "data" (Just "dev") == "data@dev")
  bracket (toAff (occupyPortImpl "127.0.0.1")) (liftEffect <<< _.close) \held -> do
    loopbackBusy <- Port.isFreeOn "127.0.0.1" held.port
    assert "a port taken on an address is not free there" (not loopbackBusy)
  bracket (toAff (occupyPortImpl "0.0.0.0")) (liftEffect <<< _.close) \held -> do
    busy <- Port.isFree held.port
    assert "taken port detected" (not busy)
    next <- Port.findFree held.port
    nextFree <- Port.isFree next
    assert "findFree increments past the taken port" (next > held.port && nextFree)
    untouched <- Port.resolve base
    assert "resolve passes options without forwards through" (Options.buildCreateArgs untouched == Options.buildCreateArgs base)
    let taken = show held.port
    resolved <- Port.resolve (base # Options.withPorts [ taken <> ":80", taken <> ":443", "127.0.0.1:" <> taken <> ":22" ])
    case Port.hostPorts resolved of
      [ a, b, c ] -> do
        assert "resolve moves every taken host port upwards" (a > held.port && b > a && c > b)
        assert "resolve keeps guest ports and bind prefixes"
          (Options.buildCreateArgs resolved == [ "linux", "alpine", "-d", "--port", show a <> ":80", "--port", show b <> ":443", "--port", "127.0.0.1:" <> show c <> ":22" ])
      _ -> assert "resolve keeps every forward" false
  let prefix = CI.workflow "test" # CI.onPush [ "main" ] # CI.deps [ "nodejs" ]
  let plan = prefix # CI.step "test" "npm test"
  assert "workflow immutable prefix" (CI.yaml prefix /= CI.yaml plan)
  bracket (liftEffect setup) (liftEffect <<< _.cleanup) \fake -> do
    box <- opts # B.create
    chained <- pure box # B.andThen B.stop # B.andThen (B.connectNetwork "devnet") # B.andThen B.start
    assert "lifecycle preserves sandbox" (B.sandboxId box == B.sandboxId chained)
    out <- liftEffect makeSink
    err <- liftEffect makeSink
    let
      execOpts = Exec.options # Exec.withStdin "input"
        # Exec.withStdout out.write
        # Exec.withStderr err.write
    result <- box # B.execWith
      [ "node", "-e", "process.stdin.resume();process.stdin.on('data',d=>process.stdout.write(d));process.stdout.write('é'.repeat(80000));process.stderr.write('err'.repeat(80000));process.exitCode=7" ]
      execOpts
    liveOut <- liftEffect out.read
    liveErr <- liftEffect err.read
    assert "nonzero exit remains result data" (result.exitCode == 7)
    assert "live stdout retained" (Exec.decodeUtf8 liveOut == result.stdout)
    assert "live stderr retained" (Exec.decodeUtf8 liveErr == result.stderr)
    args <- liftEffect fake.args
    assert "streaming does not request a PTY"
      ( args ==
          [ "exec", "abcdef123456", "node", "-e", "process.stdin.resume();process.stdin.on('data',d=>process.stdout.write(d));process.stdout.write('é'.repeat(80000));process.stderr.write('err'.repeat(80000));process.exitCode=7" ]
      )
    failed <- attempt $ box # B.execWith [ "node", "-e", "process.stdout.write('kept');process.exitCode=9" ] (Exec.options # Exec.withThrowOnError true)
    case failed of
      Left e -> case Error.commandResult e of
        Just r -> assert "throw mode retains output" (r.exitCode == 9 && r.stdout == "kept")
        Nothing -> assert "expected command error" false
      Right _ -> assert "throw mode" false
    literal <- box # B.exec [ "node", "-e", "process.stdout.write(process.argv[1])", "$(echo injected); spaced" ]
    assert "argv stays literal" (literal.stdout == "$(echo injected); spaced")
    let bytes = Exec.fromBytes [ 0, 255, 254, 10, 128 ]
    box # FS.writeFile "/tmp/data" bytes
    roundtrip <- box # FS.readFile "/tmp/data"
    assert "byte-exact files" (Exec.toBytes roundtrip == Exec.toBytes bytes)
    hit <- box # Cache.restore { key: "miss", path: null, restoreKeys: [] }
    assert "cache miss succeeds with nullable fields" (not hit.restored && toMaybe hit.key == Nothing)
    zbox <- (Options.linux "postgres" # Options.withZfs [ "data@main:/var/lib/postgresql" ]) # B.create
    zargs <- liftEffect fake.args
    assert "create passes --zfs through the CLI" (zargs == [ "linux", "postgres", "-d", "--zfs", "data@main:/var/lib/postgresql" ] && B.sandboxId zbox == "abcdef123456")
    vols <- Zfs.list
    assert "zfs volumes decode" (map _.name vols == [ "data" ] && (Array.concatMap (_.mounts) (Array.concatMap _.attachedTo vols) # map _.mountpoint) == [ "/mnt/data" ])
    created <- Zfs.branch "data" "feature" (Just "main")
    bargs <- liftEffect fake.args
    assert "zfs branch argv" (created == "data@feature" && bargs == [ "zfs", "branch", "data", "feature", "--from", "main" ])
    _ <- Zfs.attachAt "data@feature" "abcdef123456" (Just "/srv")
    aargs <- liftEffect fake.args
    assert "zfs attach argv" (aargs == [ "zfs", "attach", "data@feature", "abcdef123456", "--mount", "/srv" ])
    v <- Host.version
    assert "cli version" (v == "bsdkrun 0.0.0-test")
    engine <- Docker.status
    assert "docker status decodes" (not engine.running && toMaybe engine.machineId == Just "eeeeeeeeeeee" && engine.machineRunning && toMaybe engine.apiPort == Just 2375)
    started <- Docker.start { cpus: 2, mem: 2048, publishBind: Just "127.0.0.1" }
    startArgs <- liftEffect fake.args
    assert "docker start passes resources and the bind address, and reads the trailing JSON" (started.running && startArgs == [ "docker", "start", "--json", "--cpus", "2", "--mem", "2048", "--publish-bind", "127.0.0.1" ])
    _ <- Docker.start { cpus: 1, mem: 512, publishBind: Nothing }
    plainArgs <- liftEffect fake.args
    assert "docker start leaves the bind to bsdkrun by default" (plainArgs == [ "docker", "start", "--json", "--cpus", "1", "--mem", "512" ])
    cs <- Docker.containers true
    psArgs <- liftEffect fake.args
    assert "docker ps decodes" (map _.name cs == [ "db" ] && psArgs == [ "docker", "ps", "--json", "--all" ])
    ran <- Docker.docker [ "run", "-d", "fail" ]
    assert "host docker runs against the engine socket" (ran.exitCode == 5 && String.contains (String.Pattern "\"host\":\"unix://") ran.stdout && String.contains (String.Pattern "docker.sock") ran.stdout && String.contains (String.Pattern "[\"run\",\"-d\",\"fail\"]") ran.stdout)
    attachedCode <- box # Sandbox.execAttached false [ "node", "-e", "process.exit(3)" ]
    attachedArgs <- liftEffect fake.args
    assert "attached exec binds the terminal and yields the status" (attachedCode == 3 && attachedArgs == [ "exec", "abcdef123456", "node", "-e", "process.exit(3)" ])
    ttyCode <- box # Sandbox.execAttached true [ "node", "-e", "process.exit(0)" ]
    ttyArgs <- liftEffect fake.args
    assert "attached exec asks for a PTY with tty" (ttyCode == 0 && ttyArgs == [ "exec", "-t", "abcdef123456", "node", "-e", "process.exit(0)" ])
    liftEffect (fake.console "old boot\n")
    console <- liftEffect makeSink
    follower <- forkAff (Sandbox.streamConsoleWith console.write false box)
    delay (Milliseconds 300.0)
    liftEffect (fake.console "new boot\n")
    let
      settle n = do
        got <- liftEffect console.read
        if Exec.decodeUtf8 got /= "" || n == 0 then pure got else delay (Milliseconds 100.0) *> settle (n - 1)
    streamed <- settle 50
    killFiber (error "done") follower
    assert "console streams new output without replaying the old" (Exec.decodeUtf8 streamed == "new boot\n")
  bracket (liftEffect mockDaemon) (liftEffect <<< _.cleanup) \daemon -> do
    client <- Client.connect "http://example.test" "secret"
    _ <- client # Client.list false
    variables <- liftEffect daemon.input
    assert "remote list boolean" (variables == "{\"all\":false}")
    id <- client # Client.runLinux (Options.linux "alpine" # Options.withName "remote" # Options.withNetwork "devnet")
    assert "remote create" (id == "remote-id")
    input <- liftEffect daemon.linuxInput
    assert "remote network translated without CLI-only fields" (input.image == "alpine" && input.name == "remote" && input.network == "devnet" && not input.noNet && input.valid && input.env == [])

  liftEffect $ log "PureScript SDK tests passed"
