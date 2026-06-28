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
# command (configured in AMP, plan Task 7) invokes /opt/fika/run-headless.sh.
ENTRYPOINT ["/ampstart.sh"]
CMD []
