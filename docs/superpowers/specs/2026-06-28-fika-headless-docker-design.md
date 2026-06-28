# Dockerized Fika Headless Client on AMP — Design Spec

**Date:** 2026-06-28
**Status:** Approved design, pending implementation plan
**Owner:** Stress-CG

## 1. Objective

Add a **Fika headless client** that runs as a Docker-backed AMP instance on the
**same Linux server** as an existing, working AMP-hosted SPT server. The headless
must connect to that existing SPT backend, register itself via the `fika-server`
mod, and appear as a joinable dedicated host so players can play Fika without any
player having to host.

**Non-goals:**
- Do **not** stand up a second SPT backend. The headless is a *client* that talks
  to the existing backend.
- Do **not** modify the existing SPT server except where strictly unavoidable
  (treated as production).

## 2. Context & Constraints

### Hardware / environment
- Linux dedicated server, 96 GB RAM, ample CPU. Resource usage is not a concern.
- **No SSH and no sudo.** The box is locked down for security. The only control
  surface is the **AMP web panel**.
- **AMP runs instances as Docker containers** (AMP is configured in Docker mode).

### Confirmed facts
- Existing SPT server is reachable by players at **`205.209.116.114:6969`**
  (therefore bound to a routable interface, not localhost-only).
- A full, SPT-patched **EFT client folder** (`EscapeFromTarkov.exe` + `BepInEx/`)
  already exists on the Linux box.
- The **`fika-server`** mod is installed on the SPT backend.
- No Fika **headless profile** has been generated yet.
- Current symptom: a previously attempted headless (on a separate Windows machine)
  **never registers** — it "doesn't show it exists." Root cause is the headless
  failing to complete connection/registration with the backend across machines.
  Co-locating on the Linux box removes that failure class.

### Versions (as of 2026-06-28)
- **SPT 4.0.12** (build 40087). C#/.NET server.
- **Fika up to date** (Fika-Plugin 2.x; official `project-fika/Fika-Headless`
  component + "Fika Headless Launcher" available).
- Consequences: headless plugin file is **`Fika.Headless.dll`**; **`HTTPS=true`**
  (the `HTTPS=false` case applied only to SPT < 3.11).

## 3. Chosen Approach (Approach A)

Build a **custom Docker image `FROM cubecoders/ampbase`** that adds the headless
*runtime* (Wine + Xvfb + a launch script) while preserving AMP's `/ampstart.sh`
entrypoint so AMP fully manages the instance. Publish the image to
**`ghcr.io/Stress-CG/...`** via GitHub Actions (no machine needs a manual
`docker build`; the locked-down prod box only ever *pulls*). Create an AMP
Generic-module instance configured with `Meta.SpecificDockerImage` to use that
image, bind-mounting the existing EFT client folder and passing the headless
configuration as environment.

### Approaches considered and rejected
- **B — Generic module shells out to `docker run` on the unmodified
  `zhliau/fika-headless` image.** Rejected: AMP only supervises the launcher, not
  the real container (shallow control, messy logs), and it depends on the Generic
  instance being allowed to reach the host Docker socket, which the hardened box
  may block.
- **C — Provider runs the container outside AMP via `docker compose`.** Rejected:
  lives outside the AMP panel (user cannot self-manage), and depends on a third
  party for every change.

Approach A is the only option that keeps the headless **fully manageable from the
AMP panel the user controls**, avoids dependence on the provider, and respects the
box's lockdown.

## 4. Architecture

```text
Linux dedicated server (no shell; AMP-panel only)
│
├── AMP (ADS controller)
│     ├── [existing] SPT Server instance ── 205.209.116.114:6969  ◄── UNTOUCHED
│     │                                      (fika-server mod installed)
│     └── [NEW] Fika Headless instance ── Docker container, image FROM cubecoders/ampbase
│                ├─ outbound HTTP  ──► SPT backend :6969  (registers via fika-server)
│                ├─ bind-mount     ──► existing EFT client folder (EXE + BepInEx)
│                └─ published UDP port ◄── players connect to the headless-hosted raid
│
└── ghcr.io/Stress-CG ── AMP auto-pulls the custom image on instance create
```

### Components

| Component | Responsibility | Depends on |
|---|---|---|
| Custom AMP image (`FROM cubecoders/ampbase`) | Provide Wine + Xvfb + launch script that runs `EscapeFromTarkov.exe -batchmode -nographics` under `/ampstart.sh` | ampbase, registry |
| GitHub Actions build | Build & push the image to `ghcr.io/Stress-CG` | GitHub (Stress-CG) |
| AMP Generic instance | `Meta.SpecificDockerImage`, `CustomMountBinds`, env vars, published port; supervise start/stop/console/auto-restart | the image |
| Headless profile | One-time `fika-server`-generated dedicated profile; provides `PROFILE_ID` | existing fika-server |
| Existing SPT server | Unchanged; receives the headless registration like any client | — |

### Key design decisions and rationale
- **Bind-mount the EFT client, don't bake it in.** It is ~20 GB and already on the
  host; baking it would bloat the image and registry pull. The image carries only
  runtime (Wine/Xvfb/launch logic).
- **Build via GitHub Actions, not on the box.** No shell on prod, and prod should
  not build images. CI builds & publishes; AMP only pulls.
- **Bridge networking + published port, not host networking.** Matches AMP's
  documented behavior and keeps the instance isolated from the host network
  (security posture). Outbound to `:6969` works through NAT.

## 5. Data Flow

```text
1. AMP starts the Headless instance (container)
2. Inside: Xvfb (virtual display) → Wine → EscapeFromTarkov.exe -batchmode -nographics
3. Headless logs into the SPT backend at SERVER_URL using PROFILE_ID
4. fika-server sees the headless connect → advertises it as an available dedicated host
5. Player opens Fika → headless now appears as a joinable host   ◄── the fix
6. Player starts a raid on the headless → headless runs raid/AI; players connect
   to its published game port
```

## 6. Configuration the Instance Carries

| Setting | Value | Why |
|---|---|---|
| `Meta.SpecificDockerImage` | `ghcr.io/stress-cg/fika-headless:<tag>` | tells AMP which image to pull/run |
| `CustomMountBinds` | host EFT folder → container path | reuse existing files, avoid 20 GB in image |
| `SERVER_URL` | **to be verified** (see Risks) | where the headless registers |
| `SERVER_PORT` | `6969` | backend port |
| `PROFILE_ID` | from `fika-server` headless profile | headless login identity |
| `HTTPS` | `true` | required for SPT 4.0.x |
| published port | headless game UDP port | so players can connect to the raid |

## 7. Client-side Prep (one step)

The mounted EFT client is SPT-patched but the headless additionally requires
**`Fika.Headless.dll`** (matching the installed Fika version) in its
`BepInEx/plugins`. Presence of this DLL is **not yet confirmed** and will be an
explicit verified step, not an assumption. The headless host uses a client copy
that has this plugin.

## 8. AMP Capability Notes (verified against CubeCoders docs)

- **Custom image:** AMP requires images built `FROM cubecoders/ampbase` (retaining
  `/ampstart.sh` + `CMD []`); arbitrary third-party images cannot be run
  unmodified by a managed instance. Selected via `Meta.SpecificDockerImage`;
  public-registry images auto-download.
- **Bind mounts:** Supported via `CustomMountBinds` (host path → container path).
  Known quirk: setting it through the web UI can save blank; editing the instance
  configuration directly is the reliable method. Implementation must account for
  this.
- **Networking:** AMP uses **bridge mode with `-p` port mapping**, not host
  networking. UDP and TCP can both be published.

## 9. Verification Strategy

- **Image builds & pushes:** GitHub Actions run succeeds; image visible in
  `ghcr.io/Stress-CG`.
- **AMP pulls & starts:** instance reaches running state; AMP console shows Wine +
  Xvfb + EFT launching without fatal errors.
- **Backend connectivity:** from inside the container, the chosen `SERVER_URL:6969`
  is reachable (the decisive test that selects the correct `SERVER_URL`).
- **Registration:** the headless appears as a joinable dedicated host in a real
  Fika client.
- **End-to-end:** a player starts and loads a raid hosted by the headless.
- **Production untouched:** existing SPT server continues serving normally
  throughout.

## 10. Risks & Mitigations

| Risk | Impact | Mitigation |
|---|---|---|
| `SERVER_URL` reachability from inside container (public IP hairpin NAT vs. bridge gateway `172.17.0.1` requires SPT bound `0.0.0.0` vs. host LAN IP) | Headless can't register → "doesn't show" repeats | Empirically test each candidate from inside the container; pick the one that connects. Touches only the new instance. |
| `CustomMountBinds` web-UI blank-save bug | Client folder not mounted → headless can't launch | Set mount via instance config directly; verify the mount is present before first run. |
| `Fika.Headless.dll` missing/mismatched in client | Headless launches as a normal client, never registers as headless | Explicit step to place the correct-version DLL; verify before run. |
| Published game UDP port not reachable by players | Players see the host but can't join raids | Confirm AMP publishes the UDP port and the host firewall allows it. |
| Wine/EFT software-render instability headless | Crashes / hangs on raid load | Use official Fika-Headless launch flags; rely on Fika's built-in "terminate if no one connects in 2 min" + AMP auto-restart. |
| Editing instance config without shell | May be blocked | Confirm AMP panel exposes the needed instance settings (mount binds, env, image); if a field is missing, fall back to AMP's config editor. |

## 11. Open Items to Resolve During Implementation

1. Exact official Fika-Headless launch command/flags for SPT 4.0.x (from the
   `project-fika/Fika-Headless` docs/launcher).
2. Whether SPT backend binds `0.0.0.0` (enables bridge-gateway `SERVER_URL`).
3. Confirm `Fika.Headless.dll` presence/version in the on-box client folder.
4. The container path convention AMP expects for the bind-mounted client and how
   the launch script locates `EscapeFromTarkov.exe`.

## 12. Success Criteria

- Existing AMP-hosted SPT server continues operating normally.
- A Docker-backed AMP instance runs the Fika headless client.
- The headless connects to the existing SPT backend and registers.
- Players can use Fika normally (join a headless-hosted raid).
- The solution is documented well enough to recreate from scratch.
- Every configuration decision is understood, not copied blindly.
