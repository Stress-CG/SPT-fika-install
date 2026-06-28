# Fika Headless on AMP — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Run a Fika headless EFT client as a Docker-backed AMP instance on the same Linux box as the existing SPT server, so it registers with that backend and players can join headless-hosted raids.

**Architecture:** Custom image built `FROM cubecoders/ampbase` (Wine + Xvfb + Mesa software rendering + a launch script), published to `ghcr.io/Stress-CG` by GitHub Actions, run as an AMP Generic-module instance that bind-mounts the existing EFT client folder and registers with `205.209.116.114:6969`.

**Tech Stack:** CubeCoders AMP (Docker mode), Docker, GitHub Actions + GHCR, Wine (WineHQ), Xvfb, Mesa/llvmpipe, SPT 4.0.12, Fika 2.x.

## Global Constraints

- **SPT server is production — do not modify it** except the single, flagged headless-profile enablement in Task 4. No other backend changes.
- **No SSH/sudo on the host.** Every host-side action happens through the **AMP panel**. No step may assume a shell on the production box.
- **No second SPT backend.** The headless is a client of the existing one.
- **Do not bake the EFT client into the image.** It is bind-mounted from the host.
- **Image base:** must be `FROM cubecoders/ampbase`, retaining `ENTRYPOINT ["/ampstart.sh"]` + `CMD []` so AMP can supervise the instance.
- **Versions:** SPT **4.0.12**; Fika up to date → headless plugin **`Fika.Headless.dll`**, **`HTTPS=true`**.
- **Backend:** `SERVER_URL` host **to be determined in Task 6** (candidates: `205.209.116.114`, docker bridge gateway `172.17.0.1`, host LAN IP); `SERVER_PORT=6969`.
- **Registry:** `ghcr.io/stress-cg/fika-headless` (lowercase required by GHCR).
- **Execution style:** per the project brief, complete one task, explain the result, and wait for confirmation before the next.

## File Structure (local repo `D:\FikaHeadlessDocker`)

| Path | Responsibility |
|---|---|
| `Dockerfile` | Build the headless runtime on top of `cubecoders/ampbase` |
| `scripts/run-headless.sh` | Start Xvfb + Wine + EFT headless; AMP's instance start command |
| `.github/workflows/build.yml` | Build & push the image to GHCR |
| `amp/fika-headless.kvp` | AMP Generic-module config reference (image, ports, start cmd) |
| `docs/RUNBOOK.md` | Recreate-from-scratch operator guide (success criterion) |
| `docs/superpowers/specs/2026-06-28-fika-headless-docker-design.md` | Approved design (exists) |

---

### Task 1: Repo scaffolding

**Files:**
- Create: `.gitignore`, `README.md`

**Goal:** A clean repo skeleton so subsequent artifacts have a home and history.

- [ ] **Step 1: Create `.gitignore`**

```gitignore
# local
*.log
.DS_Store
# never commit secrets or game files
*.env
secrets/
tarkov/
```

- [ ] **Step 2: Create `README.md`**

```markdown
# Fika Headless on AMP

Custom AMP (Docker-mode) instance that runs a Fika headless EFT client and
registers with an existing SPT backend. See `docs/superpowers/specs/` for the
design and `docs/RUNBOOK.md` for operator steps.
```

- [ ] **Step 3: Commit**

```
git add .gitignore README.md
git commit -m "chore: repo scaffolding"
```

**Expected Result:** Repo has README + gitignore on `main`.
**Verification:** `git log --oneline` shows the commit; `git status` clean.
**Risks:** None.

---

### Task 2: Headless launch script

**Files:**
- Create: `scripts/run-headless.sh`

**Interfaces:**
- Consumes (env, provided by the AMP instance in Task 7): `PROFILE_ID`, `SERVER_URL`, `SERVER_PORT`, `HTTPS`, `EFT_DIR`.
- Produces: an executable AMP start command at `/opt/fika/run-headless.sh` inside the image.

**Goal:** A minimal, software-render-only adaptation of the proven `zhliau` launch logic — no Pelican/DGPU/ntsync/wine-GE complexity.

- [ ] **Step 1: Write `scripts/run-headless.sh`**

```bash
#!/bin/bash -e
# Fika headless launch — software rendering only (no GPU).
# Adapted from zhliau/fika-headless-docker entrypoint.sh (proven launch line).

EFT_DIR=${EFT_DIR:-/opt/tarkov}
EFT_BIN="$EFT_DIR/EscapeFromTarkov.exe"
BEPINEX_LOG="$EFT_DIR/BepInEx/LogOutput.log"
SERVER_PORT=${SERVER_PORT:-6969}
HTTPS=${HTTPS:-true}
PROTO=https; [ "$HTTPS" != "true" ] && PROTO=http

export DISPLAY=:0
export WINEDEBUG=-all
# Force software OpenGL (llvmpipe) so Wine's wined3d has a GL context with no GPU.
export LIBGL_ALWAYS_SOFTWARE=1
export GALLIUM_DRIVER=llvmpipe

if [ ! -f "$EFT_BIN" ]; then
  echo "FATAL: $EFT_BIN not found. Is the client folder mounted to $EFT_DIR?" >&2
  exit 1
fi
if [ -z "$PROFILE_ID" ] || [ -z "$SERVER_URL" ]; then
  echo "FATAL: PROFILE_ID and SERVER_URL must be set." >&2
  exit 1
fi

start_xvfb() {
  pkill Xvfb 2>/dev/null || true
  rm -f /tmp/.X0-lock
  echo "Starting Xvfb on :0"
  Xvfb :0 -screen 0 1024x768x24 -ac +extension GLX +render -noreset \
    -nolisten tcp -nolisten unix 2>&1 &
}

echo "wineboot --update (first run ~60s)"
wine wineboot --update >/dev/null 2>&1 || true

start_xvfb
echo "Connecting headless to $PROTO://$SERVER_URL:$SERVER_PORT"

# Stream BepInEx log into AMP console for visibility.
( sleep 5; tail -F -n 0 "$BEPINEX_LOG" 2>/dev/null ) &

exec wine "$EFT_BIN" -batchmode -nographics -noDynamicAI \
  -token="$PROFILE_ID" \
  -config="{'BackendUrl':'$PROTO://$SERVER_URL:$SERVER_PORT','Version':'live'}"
```

- [ ] **Step 2: Mark intent for executable bit (set in Dockerfile Task 3)**

Note: Windows checkout can't preserve the +x bit; the Dockerfile runs `chmod +x`. No action beyond writing the file.

- [ ] **Step 3: Commit**

```
git add scripts/run-headless.sh
git commit -m "feat: headless launch script (software render)"
```

**Expected Result:** A launch script that fails loudly on missing mount/env and otherwise runs the proven EFT headless command.
**Verification:** `bash -n scripts/run-headless.sh` reports no syntax errors.
**Risks:** `LIBGL_ALWAYS_SOFTWARE`/`GALLIUM_DRIVER` may be insufficient if EFT requires Vulkan even under `-nographics`; if so, Task 7 verification will reveal it and the fallback is DXVK + `lavapipe` (documented in Task 7 Risks).

---

### Task 3: Dockerfile + CI build to GHCR

**Files:**
- Create: `Dockerfile`, `.github/workflows/build.yml`

**Interfaces:**
- Produces: image `ghcr.io/stress-cg/fika-headless:latest` consumed by AMP in Task 7.

**Goal:** Build the runtime on `ampbase` and publish it without any shell on prod. The CI build is the verification loop for package names / base OS.

- [ ] **Step 1: Write `Dockerfile`**

```dockerfile
FROM cubecoders/ampbase

USER root

# ampbase is Debian-based. Use WineHQ for a current Wine (Debian's is too old for EFT).
# Mesa provides llvmpipe (software OpenGL); wined3d translates EFT's DirectX 11 to GL.
RUN dpkg --add-architecture i386 \
 && apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl gnupg \
 && mkdir -p /etc/apt/keyrings \
 && curl -fsSL https://dl.winehq.org/wine-builds/winehq.key \
      -o /etc/apt/keyrings/winehq-archive.key \
 && . /etc/os-release \
 && curl -fsSL "https://dl.winehq.org/wine-builds/debian/dists/${VERSION_CODENAME}/winehq-${VERSION_CODENAME}.sources" \
      -o /etc/apt/sources.list.d/winehq.sources \
 && apt-get update \
 && apt-get install -y --no-install-recommends \
      winehq-stable \
      xvfb \
      libgl1-mesa-dri mesa-vulkan-drivers \
      cabextract winbind \
 && apt-get clean && rm -rf /var/lib/apt/lists/*

COPY scripts/run-headless.sh /opt/fika/run-headless.sh
RUN chmod +x /opt/fika/run-headless.sh && mkdir -p /opt/fika/.wine /opt/tarkov

ENV WINEPREFIX=/opt/fika/.wine \
    WINEARCH=win64 \
    WINEDEBUG=-all \
    EFT_DIR=/opt/tarkov \
    DISPLAY=:0

# AMP supervises the process; keep ampbase's entrypoint. The instance's start
# command (configured in AMP, Task 7) invokes /opt/fika/run-headless.sh.
ENTRYPOINT ["/ampstart.sh"]
CMD []
```

- [ ] **Step 2: Write `.github/workflows/build.yml`**

```yaml
name: build
on:
  push:
    branches: [main]
    paths: ['Dockerfile', 'scripts/**', '.github/workflows/build.yml']
  workflow_dispatch:

jobs:
  build:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      packages: write
    steps:
      - uses: actions/checkout@v4
      - uses: docker/login-action@v3
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}
      - uses: docker/build-push-action@v6
        with:
          context: .
          push: true
          tags: ghcr.io/stress-cg/fika-headless:latest
```

- [ ] **Step 3: Commit and push to trigger the build**

```
git add Dockerfile .github/workflows/build.yml
git commit -m "feat: ampbase headless image + GHCR build"
# push requires the GitHub remote (set up in this task's first run)
```

- [ ] **Step 4: Watch the Actions run**

Run (or watch in the GitHub UI): the `build` workflow on `main`.
Expected: **green**. If it fails on `apt-get`/package names, read the log — that is the base-OS verification — and adjust package names, then re-push.

- [ ] **Step 5: Make the GHCR package readable by AMP**

In GitHub → the `fika-headless` package → Package settings → set visibility to **public** (simplest; AMP then pulls without auth), or note credentials for a private pull in Task 7.

**Expected Result:** `ghcr.io/stress-cg/fika-headless:latest` exists and is pullable.
**Verification:** Actions run green; the package appears under the Stress-CG org packages.
**Risks:** WineHQ `.sources` codename mismatch if `ampbase` is a non-standard base → the build log names the bad codename; fix `VERSION_CODENAME` handling. Image size is fine (no game files).

---

### Task 4: Generate the headless profile on the SPT server *(touches production — flagged)*

**Goal:** Obtain a `PROFILE_ID` for the headless to log in as. This is the one allowed production change.

- [ ] **Step 1: Locate the fika-server config**

In the AMP file manager for the SPT instance, open `user/mods/fika-server/assets/configs/fika.jsonc` (confirm exact filename — recent Fika uses `fika.jsonc`).

- [ ] **Step 2: Enable headless profile generation**

Find the `headless` → `profiles` → `amount` setting and set it to `1` (confirm the exact key name in your version's file before saving). Save.

- [ ] **Step 3: Restart the SPT instance and read the profile id**

Restart the SPT instance from AMP. In the SPT console/log, `fika-server` logs the created headless profile id on startup. Record the **`PROFILE_ID`**.

**Expected Result:** One headless profile exists; its id is recorded.
**Verification:** The SPT console shows a line referencing a created/available headless profile and its id; players still connect normally (production unaffected).
**Risks:** Exact config key differs by Fika version → confirm against the actual file before editing; do not guess the key. Restarting SPT briefly disconnects players — schedule it.

---

### Task 5: Confirm the headless plugin in the client folder

**Goal:** Ensure the mounted client can actually run as a headless host.

- [ ] **Step 1: Inspect the client's plugins**

In the AMP file manager, browse the EFT client folder → `BepInEx/plugins/`. Confirm **`Fika.Headless.dll`** is present (separate from the normal Fika co-op plugin).

- [ ] **Step 2: If missing, add it**

Download the **Fika-Headless** plugin matching your installed Fika version and place `Fika.Headless.dll` in `BepInEx/plugins/`. Do not mix versions.

**Expected Result:** `Fika.Headless.dll` present and version-matched.
**Verification:** File listing shows the DLL; its version matches the installed Fika.
**Risks:** Version mismatch → headless launches as a normal client and never registers. Confirm versions, don't assume.

---

### Task 6: Determine the working `SERVER_URL`

**Goal:** Pick the backend address the container can actually reach, empirically.

- [ ] **Step 1: Prefer the bridge gateway if SPT binds all interfaces**

Check the SPT `http.json` (`SPT_Data/Server/configs/http.json` or equivalent) for the backend bind ip. If it is `0.0.0.0`, the docker bridge gateway `172.17.0.1` is the cleanest `SERVER_URL` (stays on-host, no hairpin). Record the bind ip.

- [ ] **Step 2: Order the candidates to try in Task 7**

Record this priority for Task 7's first boot:
1. `172.17.0.1` (only if bind ip is `0.0.0.0`)
2. host LAN ip (if known)
3. `205.209.116.114` (public; relies on NAT hairpin)

**Expected Result:** A prioritized `SERVER_URL` list, decided by the actual bind ip.
**Verification:** Confirmed in Task 7 when the headless connects (BepInEx log shows backend connection, no connection-refused/timeout).
**Risks:** If none connect, the bind/firewall is the issue — adjust only the new instance / ask the provider; never loosen the production server blindly.

---

### Task 7: Create and start the AMP Generic instance

**Files:**
- Create: `amp/fika-headless.kvp` (reference copy of the config)

**Goal:** A managed AMP instance that pulls the image, mounts the client, passes config, publishes the game port, and runs the launch script.

- [ ] **Step 1: Create a Generic-module instance** in AMP (Docker-backed).

- [ ] **Step 2: Point it at the custom image** — set `Meta.SpecificDockerImage=ghcr.io/stress-cg/fika-headless:latest` (via the instance config; confirm the field in the AMP Generic-module settings).

- [ ] **Step 3: Bind-mount the client** — set `CustomMountBinds` mapping the host EFT client folder → `/opt/tarkov`. Set it via the instance configuration directly (the web-UI field is known to save blank — verify the value persisted).

- [ ] **Step 4: Set environment** — `PROFILE_ID` (Task 4), `SERVER_URL` (Task 6, first candidate), `SERVER_PORT=6969`, `HTTPS=true`, `EFT_DIR=/opt/tarkov`.

- [ ] **Step 5: Set the start command** to `/opt/fika/run-headless.sh`.

- [ ] **Step 6: Publish the game port** — map the Fika headless game UDP port so players can reach the raid host (confirm the port your Fika uses; default examples use `25565/udp`). Add the matching host firewall allowance via the provider if needed.

- [ ] **Step 7: Record the config** in `amp/fika-headless.kvp` and commit it (no secrets).

- [ ] **Step 8: Start the instance and watch the AMP console.**

Expected sequence in the console: `wineboot --update` → `Starting Xvfb on :0` → `Connecting headless to https://<SERVER_URL>:6969` → BepInEx log lines indicating backend connection and Fika headless init.
If the backend line shows refused/timeout, stop, switch `SERVER_URL` to the next Task 6 candidate, restart.

**Expected Result:** Instance reaches running state and connects to the backend.
**Verification:** AMP console shows the connect line and BepInEx headless init with no fatal Wine/graphics error.
**Risks:**
- **Software render insufficient:** if Wine fails to create a device even with llvmpipe, switch the image to DXVK + `lavapipe` (`mesa-vulkan-drivers` already present; install `dxvk`, set `WINEDLLOVERRIDES` for d3d11/dxgi, `VK_ICD_FILENAMES` to lavapipe). Re-build via CI, restart instance.
- **Mount blank-saved:** the script's `FATAL: EscapeFromTarkov.exe not found` makes this obvious immediately.

---

### Task 8: End-to-end registration and raid

**Goal:** Prove the original symptom ("doesn't show it exists") is fixed.

- [ ] **Step 1:** In a real Fika client, confirm the headless now appears as a joinable dedicated host.
- [ ] **Step 2:** Start and load into a raid hosted by the headless; confirm players connect to the published port.
- [ ] **Step 3 (optional):** Enable `AUTO_RESTART_ON_RAID_END`-style behavior later if memory growth across raids warrants it (96 GB gives headroom; revisit only if needed — YAGNI).

**Expected Result:** Headless visible; a raid loads and is playable.
**Verification:** Visual confirmation in-client + a successful raid load with a second player.
**Risks:** Port not reachable externally → players see the host but can't join; verify the published UDP port end-to-end from outside the network.

---

### Task 9: Runbook

**Files:**
- Create: `docs/RUNBOOK.md`

**Goal:** Recreate-from-scratch documentation (success criterion).

- [ ] **Step 1:** Write `docs/RUNBOOK.md` capturing: the final image tag, the exact AMP instance settings (image, mount, env incl. the chosen `SERVER_URL`, start command, published port), how the `PROFILE_ID` was generated, and the troubleshooting branch (software-render fallback, `SERVER_URL` candidates).
- [ ] **Step 2:** Commit.

```
git add docs/RUNBOOK.md
git commit -m "docs: operator runbook"
```

**Expected Result:** Anyone can rebuild the setup from the repo.
**Verification:** A reader can follow it without re-deriving decisions.
**Risks:** Drift if settings change later — update the runbook when they do.

---

## Self-Review

**Spec coverage:** Objective → Tasks 7–8; custom ampbase image → Task 3; GH Actions/GHCR → Task 3; bind-mount → Task 7; headless profile → Task 4; `Fika.Headless.dll` → Task 5; `SERVER_URL` verification → Task 6/7; published port → Task 7; production-untouched → Global Constraints + Task 4 flag; runbook/success criteria → Task 9. No spec section unmapped.

**Placeholder scan:** The only deferred values (`SERVER_URL` choice, exact Fika config key in Task 4, the game UDP port) are explicit *verify-against-the-live-system* steps with stated methods — not lazy placeholders. All code artifacts are complete.

**Type/name consistency:** Env names (`PROFILE_ID`, `SERVER_URL`, `SERVER_PORT`, `HTTPS`, `EFT_DIR`), the mount target `/opt/tarkov`, the script path `/opt/fika/run-headless.sh`, and the image tag `ghcr.io/stress-cg/fika-headless:latest` are used identically across Tasks 2, 3, 7.
