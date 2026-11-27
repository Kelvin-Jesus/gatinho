# Ambiente de teste do Gatinho no Linux: Swift + cabeçalhos do X11 + Xvfb (tela virtual).
FROM swift:latest
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      libx11-dev libxext-dev libxi-dev pkg-config \
      xvfb x11-apps xdotool imagemagick xcompmgr openbox \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /src
