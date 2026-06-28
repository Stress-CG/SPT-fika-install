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
