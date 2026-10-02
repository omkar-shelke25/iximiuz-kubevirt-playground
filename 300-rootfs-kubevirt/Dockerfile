# syntax=docker/dockerfile:1
#
# iximiuz Labs rootfs images for a multi-node K3s cluster with KubeVirt:
#
#   --target cplane       K3s server at 172.16.0.2, applies KubeVirt at boot
#   --target node         K3s agent, joins 172.16.0.2
#   --target dev-machine  Docker, kubectl, virtctl, code-server (no K3s)
#
# Each target builds on the matching official iximiuz rootfs, so K3s, the join
# token, sshd, the laborant user and the kubeconfig setup come from there.
# All three get the Catppuccin Mocha terminal used in the Rust and OpenTofu playgrounds.

ARG CPLANE_BASE=ghcr.io/iximiuz/labs/rootfs:ubuntu-k3s-server
ARG NODE_BASE=ghcr.io/iximiuz/labs/rootfs:ubuntu-k3s-agent
ARG DEV_BASE=ghcr.io/iximiuz/labs/rootfs:ubuntu-k3s-dev-machine
ARG BUILDER_BASE=ghcr.io/iximiuz/labs/rootfs:ubuntu-k3s-bare

# =============================================================================
# Stage: tools
# Prebuilt release binaries for the terminal. Archives never reach the final images.
# =============================================================================
FROM ${BUILDER_BASE} AS tools

ARG STARSHIP_VERSION=1.26.0
ARG EZA_VERSION=0.23.5
ARG BAT_VERSION=0.26.1
ARG FD_VERSION=10.5.0
ARG ZOXIDE_VERSION=0.10.0
ARG DELTA_VERSION=0.19.2
ARG ATUIN_VERSION=18.22.0
ARG LAZYGIT_VERSION=0.65.1
ARG FASTFETCH_VERSION=2.68.1

USER root
ENV HOME=/root

RUN <<EOR
set -eu
gh=https://github.com
musl=x86_64-unknown-linux-musl
bin=/opt/tools/bin
mkdir -p "$bin" /opt/fastfetch

curl -fsSL "$gh/starship/starship/releases/download/v${STARSHIP_VERSION}/starship-${musl}.tar.gz" \
  | tar -xz -C "$bin" starship
curl -fsSL "$gh/eza-community/eza/releases/download/v${EZA_VERSION}/eza_${musl}.tar.gz" \
  | tar -xz -C "$bin" ./eza
curl -fsSL "$gh/sharkdp/bat/releases/download/v${BAT_VERSION}/bat-v${BAT_VERSION}-${musl}.tar.gz" \
  | tar -xz --strip-components=1 -C "$bin" "bat-v${BAT_VERSION}-${musl}/bat"
curl -fsSL "$gh/sharkdp/fd/releases/download/v${FD_VERSION}/fd-v${FD_VERSION}-${musl}.tar.gz" \
  | tar -xz --strip-components=1 -C "$bin" "fd-v${FD_VERSION}-${musl}/fd"
curl -fsSL "$gh/ajeetdsouza/zoxide/releases/download/v${ZOXIDE_VERSION}/zoxide-${ZOXIDE_VERSION}-${musl}.tar.gz" \
  | tar -xz -C "$bin" zoxide
curl -fsSL "$gh/dandavison/delta/releases/download/${DELTA_VERSION}/delta-${DELTA_VERSION}-${musl}.tar.gz" \
  | tar -xz --strip-components=1 -C "$bin" "delta-${DELTA_VERSION}-${musl}/delta"
curl -fsSL "$gh/atuinsh/atuin/releases/download/v${ATUIN_VERSION}/atuin-${musl}.tar.gz" \
  | tar -xz --strip-components=1 -C "$bin" "atuin-${musl}/atuin"
curl -fsSL "$gh/jesseduffield/lazygit/releases/download/v${LAZYGIT_VERSION}/lazygit_${LAZYGIT_VERSION}_linux_x86_64.tar.gz" \
  | tar -xz -C "$bin" lazygit
curl -fsSL "$gh/fastfetch-cli/fastfetch/releases/download/${FASTFETCH_VERSION}/fastfetch-linux-amd64.tar.gz" \
  | tar -xz --strip-components=2 -C /opt/fastfetch

chmod 0755 "$bin"/*
EOR

# =============================================================================
# Stage: kubevirt
# virtctl, the K3s auto-deploy manifests, and preloaded image tarballs.
# =============================================================================
FROM ${BUILDER_BASE} AS kubevirt

ARG KUBEVIRT_VERSION=v1.9.0
ARG PRELOAD_IMAGES=true

USER root
ENV HOME=/root

COPY kubevirt/20-kubevirt-cr.yaml /out/manifests/20-kubevirt-cr.yaml
COPY kubevirt/preload-images.sh /tmp/preload-images.sh

RUN <<EOR
set -eu
mkdir -p /out/bin /out/images/cplane /out/images/node
echo "${KUBEVIRT_VERSION}" > /out/kubevirt-version

curl -fsSL -o /out/bin/virtctl \
  "https://github.com/kubevirt/kubevirt/releases/download/${KUBEVIRT_VERSION}/virtctl-${KUBEVIRT_VERSION}-linux-amd64"
chmod 0755 /out/bin/virtctl

# The operator runs with 1 replica instead of 2.
curl -fsSL -o /out/manifests/10-kubevirt-operator.yaml \
  "https://github.com/kubevirt/kubevirt/releases/download/${KUBEVIRT_VERSION}/kubevirt-operator.yaml"
yq -i '(select(.kind == "Deployment" and .metadata.name == "virt-operator") | .spec.replicas) = 1' \
  /out/manifests/10-kubevirt-operator.yaml

if [ "${PRELOAD_IMAGES}" = "true" ]; then
  sh /tmp/preload-images.sh "${KUBEVIRT_VERSION}" /out/images
else
  echo "image preloading disabled"
fi
EOR

# =============================================================================
# Target: cplane (K3s server)
# =============================================================================
FROM ${CPLANE_BASE} AS cplane

ARG LAB_USER=laborant

USER root
ENV HOME=/root

COPY --from=tools /opt/tools/bin/ /usr/local/bin/
COPY --from=tools /opt/fastfetch/ /usr/local/
COPY --from=kubevirt /out/bin/virtctl /usr/local/bin/virtctl
COPY --from=kubevirt /out/kubevirt-version /etc/kubevirt-version

# K3s applies every file in this folder at boot, in file name order,
# and retries until each one succeeds.
COPY --from=kubevirt /out/manifests/ /var/lib/rancher/k3s/server/manifests/
COPY --from=kubevirt /out/images/cplane/ /var/lib/rancher/k3s/agent/images/

COPY kubevirt/selinuxfs-unmount.sh /opt/iximiuz-labs/selinuxfs-unmount.sh
COPY kubevirt/selinuxfs-unmount.service /etc/systemd/system/selinuxfs-unmount.service
RUN <<EOR
set -eu
chmod 0755 /opt/iximiuz-labs/selinuxfs-unmount.sh
mkdir -p /etc/systemd/system/k3s.service.wants
ln -s /etc/systemd/system/selinuxfs-unmount.service \
  /etc/systemd/system/multi-user.target.wants/selinuxfs-unmount.service
ln -s /etc/systemd/system/selinuxfs-unmount.service \
  /etc/systemd/system/k3s.service.wants/selinuxfs-unmount.service
test -f /var/lib/rancher/k3s/server/manifests/10-kubevirt-operator.yaml
test -f /var/lib/rancher/k3s/server/manifests/20-kubevirt-cr.yaml
EOR

RUN --mount=type=bind,source=terminal,target=/tmp/terminal \
    LAB_USER=${LAB_USER} bash /tmp/terminal/setup.sh

USER $LAB_USER
ENV HOME=/home/$LAB_USER
RUN zsh -ic 'exit' && rm -f "$HOME"/.zcompdump*

# =============================================================================
# Target: node (K3s agent)
# =============================================================================
FROM ${NODE_BASE} AS node

ARG LAB_USER=laborant

USER root
ENV HOME=/root

COPY --from=tools /opt/tools/bin/ /usr/local/bin/
COPY --from=tools /opt/fastfetch/ /usr/local/
COPY --from=kubevirt /out/kubevirt-version /etc/kubevirt-version
COPY --from=kubevirt /out/images/node/ /var/lib/rancher/k3s/agent/images/

COPY kubevirt/selinuxfs-unmount.sh /opt/iximiuz-labs/selinuxfs-unmount.sh
COPY kubevirt/selinuxfs-unmount.service /etc/systemd/system/selinuxfs-unmount.service
RUN <<EOR
set -eu
chmod 0755 /opt/iximiuz-labs/selinuxfs-unmount.sh
mkdir -p /etc/systemd/system/k3s-agent.service.wants
ln -s /etc/systemd/system/selinuxfs-unmount.service \
  /etc/systemd/system/multi-user.target.wants/selinuxfs-unmount.service
ln -s /etc/systemd/system/selinuxfs-unmount.service \
  /etc/systemd/system/k3s-agent.service.wants/selinuxfs-unmount.service
EOR

RUN --mount=type=bind,source=terminal,target=/tmp/terminal \
    LAB_USER=${LAB_USER} bash /tmp/terminal/setup.sh

USER $LAB_USER
ENV HOME=/home/$LAB_USER
RUN zsh -ic 'exit' && rm -f "$HOME"/.zcompdump*

# =============================================================================
# Target: dev-machine (Docker, kubectl, virtctl, code-server; no K3s)
# =============================================================================
FROM ${DEV_BASE} AS dev-machine

ARG LAB_USER=laborant

USER root
ENV HOME=/root

COPY --from=tools /opt/tools/bin/ /usr/local/bin/
COPY --from=tools /opt/fastfetch/ /usr/local/
COPY --from=kubevirt /out/bin/virtctl /usr/local/bin/virtctl
COPY --from=kubevirt /out/kubevirt-version /etc/kubevirt-version

RUN --mount=type=bind,source=terminal,target=/tmp/terminal \
    LAB_USER=${LAB_USER} bash /tmp/terminal/setup.sh

RUN docker --version && virtctl version --client

USER $LAB_USER
ENV HOME=/home/$LAB_USER

# code-server extensions. A missing extension only prints a warning.
RUN <<EOR
set -u
for ext in catppuccin.catppuccin-vsc redhat.vscode-yaml ms-kubernetes-tools.vscode-kubernetes-tools; do
  code-server --install-extension "$ext" || echo "WARNING: could not install ${ext}"
done
EOR

# code-server: zsh login terminal, Catppuccin Mocha theme, Kubernetes YAML schemas.
# The font list lets a locally installed Nerd Font draw icons after `icons on`.
# Merges into the settings the base image already ships.
RUN <<EOR
set -eu
dir="$HOME/.local/share/code-server/User"
mkdir -p "$dir"
cat > /tmp/kubevirt-settings.json <<'JSON'
{
  "workbench.colorTheme": "Catppuccin Mocha",
  "terminal.integrated.defaultProfile.linux": "zsh",
  "terminal.integrated.profiles.linux": {
    "zsh": { "path": "zsh", "args": ["-l"] },
    "bash": { "path": "bash", "args": ["-l"] }
  },
  "terminal.integrated.fontFamily": "'JetBrainsMono Nerd Font', 'JetBrains Mono', Menlo, Consolas, monospace",
  "terminal.integrated.fontSize": 14,
  "terminal.integrated.lineHeight": 1.2,
  "terminal.integrated.cursorStyle": "line",
  "terminal.integrated.cursorBlinking": true,
  "terminal.integrated.smoothScrolling": true,
  "terminal.integrated.scrollback": 10000,
  "editor.fontSize": 14,
  "editor.smoothScrolling": true,
  "editor.cursorSmoothCaretAnimation": "on",
  "editor.bracketPairColorization.enabled": true,
  "editor.guides.bracketPairs": "active",
  "yaml.schemas": { "kubernetes": "*.yaml" }
}
JSON
if [ -s "$dir/settings.json" ]; then
  jq -s '.[0] * .[1]' "$dir/settings.json" /tmp/kubevirt-settings.json > /tmp/kubevirt-merged.json
  mv /tmp/kubevirt-merged.json "$dir/settings.json"
else
  mv /tmp/kubevirt-settings.json "$dir/settings.json"
fi
rm -f /tmp/kubevirt-settings.json
EOR

RUN zsh -ic 'exit' && rm -f "$HOME"/.zcompdump*

COPY --chown=${LAB_USER}:${LAB_USER} dev-machine/welcome $HOME/.welcome
COPY --chown=${LAB_USER}:${LAB_USER} dev-machine/testvm.yaml $HOME/testvm.yaml
RUN sed -i "s/KUBEVIRT_VERSION/$(cat /etc/kubevirt-version)/" $HOME/testvm.yaml
