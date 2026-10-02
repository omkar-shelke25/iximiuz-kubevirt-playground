# iximiuz-kubevirt-playground

Custom [iximiuz Labs](https://labs.iximiuz.com) rootfs images for a multi-node K3s cluster with KubeVirt, CDI, and the KubeVirt Manager web UI preinstalled, ready to run virtual machines as soon as the playground starts.

The layout matches the official iximiuz `k3s` playground: one dev machine with Docker, one control plane node, and two worker nodes.

| Machine | IP | Image | Role |
|---|---|---|---|
| `dev-machine` | 172.16.0.5 | `ghcr.io/omkar-shelke25/kubevirt-playground:dev-machine` | Docker, kubectl, virtctl, helm, k9s, code-server. No K3s. |
| `cplane-01` | 172.16.0.2 | `ghcr.io/omkar-shelke25/kubevirt-playground:cplane` | K3s server, KubeVirt and CDI control plane, KubeVirt Manager UI, can also run VMs |
| `node-01` | 172.16.0.3 | `ghcr.io/omkar-shelke25/kubevirt-playground:node` | K3s agent, runs VMs |
| `node-02` | 172.16.0.4 | `ghcr.io/omkar-shelke25/kubevirt-playground:node` | K3s agent, runs VMs |

## Repository layout

```
.
├── README.md
├── .github/workflows/
│   └── build-rootfs.yml              # builds and pushes all three images to GHCR
└── 300-rootfs-kubevirt/
    ├── Dockerfile                    # one file, three targets: cplane, node, dev-machine
    ├── manifest.yaml                 # iximiuz Labs playground manifest (4 machines)
    ├── terminal/
    │   └── setup.sh                  # Tokyo Night terminal, run in every target
    ├── vnc/
    │   ├── vm-vnc                    # VM screen in the browser: virtctl vnc + websockify + noVNC
    │   └── index.html                # noVNC landing page with autoconnect
    ├── kubevirt/
    │   ├── 20-kubevirt-cr.yaml       # KubeVirt CR: emulation on, 1 replica
    │   ├── 40-cdi-cr.yaml            # CDI CR: infra pinned to the K3s server
    │   ├── preload-images.sh         # pulls images per node role
    │   ├── selinuxfs-unmount.sh      # SELinux workaround (see below)
    │   └── selinuxfs-unmount.service # runs the workaround before K3s starts
    └── dev-machine/
        ├── testvm.yaml               # CirrOS test VM, copied to ~/testvm.yaml
        └── welcome                   # login banner
```

## How the images are built

Each target builds `FROM` the matching official iximiuz rootfs, so K3s, the cluster join token, sshd, the `laborant` user, and the kubeconfig setup all come from there:

| Target | Base image | What the base already does |
|---|---|---|
| `cplane` | `ghcr.io/iximiuz/labs/rootfs:ubuntu-k3s-server` | `k3s server` with `--tls-san 172.16.0.2`, enabled at boot |
| `node` | `ghcr.io/iximiuz/labs/rootfs:ubuntu-k3s-agent` | `k3s agent` joining `https://172.16.0.2:6443`, enabled at boot |
| `dev-machine` | `ghcr.io/iximiuz/labs/rootfs:ubuntu-k3s-dev-machine` | Docker CE with buildx and compose, nerdctl, kubectl, helm, k9s, krew, kexp. Copies the kubeconfig from `cplane-01` over SSH at boot. |

Two helper stages run once and feed all three targets:

| Stage | Produces |
|---|---|
| `tools` | Terminal binaries from GitHub releases |
| `kubevirt` | `virtctl`, the KubeVirt, CDI, and KubeVirt Manager manifests, and preloaded image tarballs |

What each target adds on top of its base:

| | `cplane` | `node` | `dev-machine` |
|---|---|---|---|
| KubeVirt, CDI, and KubeVirt Manager manifests in `/var/lib/rancher/k3s/server/manifests/` | Yes | | |
| Preloaded images | 13 (see below) | 4 | |
| `selinuxfs-unmount.service` | Before `k3s.service` | Before `k3s-agent.service` | |
| `virtctl` | Yes | | Yes |
| `novnc`, `websockify`, `vm-vnc` | Yes | | Yes |
| Tokyo Night terminal | Yes | Yes | Yes |
| code-server theme and Kubernetes extensions | | | Yes |
| `~/testvm.yaml` and welcome banner | | | Yes |

### Install at boot

K3s applies every YAML file in `/var/lib/rancher/k3s/server/manifests/` when the server starts, in file name order, and keeps retrying until each one succeeds. The `cplane` image puts five files there:

| File | Source | Changes from upstream |
|---|---|---|
| `10-kubevirt-operator.yaml` | KubeVirt `v1.9.0` release | `virt-operator` at 1 replica |
| `20-kubevirt-cr.yaml` | This repo | `useEmulation: true`, `infra.replicas: 1` |
| `30-cdi-operator.yaml` | CDI `v1.66.1` release | `cdi-operator` pinned to the K3s server |
| `40-cdi-cr.yaml` | This repo | CDI infra pods pinned to the K3s server, `HonorWaitForFirstConsumer` on |
| `50-kubevirt-manager.yaml` | KubeVirt Manager `v1.5.4` `bundled.yaml` | Pinned to the K3s server, Service as NodePort `30080`, image `:1.5.4` instead of `:nightly` |

The pinning keeps every infra pod on `cplane-01`, where its image is preloaded, and leaves the worker nodes free for VMs.

> [!NOTE]
> If the `kubevirtmanager/kubevirt-manager:<version>` tag doesn't exist on Docker Hub at build time, the build prints a warning and keeps upstream's `:nightly` image.

### CDI and storage

CDI imports VM disk images into PersistentVolumeClaims, so VMs can have disks that survive a restart. It uses K3s' built-in `local-path` StorageClass, which is the default.

| Point | Detail |
|---|---|
| Where disks live | On the node's own disk, under `/var/lib/rancher/k3s/storage/` |
| When a disk is created | When the VM is scheduled, on that VM's node (`WaitForFirstConsumer`) |
| Live migration | Not possible, because the disk is local to one node |
| Disk resize | Not supported by `local-path`, so KubeVirt Manager's resize option won't work |

### KubeVirt Manager

The web UI opens in the playground's **KubeVirt Manager** tab, which points at NodePort `30080` on `cplane-01`. It lists VMs, starts and stops them, and opens a VNC console in the browser.

> [!WARNING]
> KubeVirt Manager has no login, and its ClusterRole can manage resources across the whole cluster. Anyone with the tab's link controls your VMs. Keep the playground's access set to `owner`, which is the default in `manifest.yaml`.

The upstream operator places `virt-operator`, `virt-api`, and `virt-controller` on control plane nodes. That works unchanged here, because `cplane-01` is a real K3s server with the `node-role.kubernetes.io/control-plane` label. `virt-handler` runs on all three nodes, so VMs can land on any of them.

### Preloaded images

K3s imports every image tarball in `/var/lib/rancher/k3s/agent/images/` at boot. `preload-images.sh` pulls each image once and gives each node role only what it runs:

| Image | `cplane` | `node` |
|---|---|---|
| `virt-operator`, `virt-api`, `virt-controller`, `virt-exportproxy` | Yes | |
| `virt-handler`, `virt-launcher` | Yes | Yes |
| `cirros-container-disk-demo` (disk for `~/testvm.yaml`) | Yes | Yes |
| `cdi-operator`, `cdi-apiserver`, `cdi-controller`, `cdi-uploadproxy` | Yes | |
| `cdi-importer` | Yes | Yes |
| `kubevirt-manager` | Yes | |

KubeVirt and CDI images come from `quay.io/kubevirt`, and KubeVirt Manager from `docker.io/kubevirtmanager`. If one can't be pulled at build time, the build prints a warning and carries on, and that image is pulled at runtime instead.

## Why KubeVirt needs these changes on iximiuz Labs

### No nested virtualization, so emulation

Playground VMs run on Firecracker, which doesn't pass Intel VMX or AMD SVM to the guest, so there is no `/dev/kvm`. The KubeVirt CR sets `useEmulation: true` from the start, so VMs run with QEMU software emulation instead of staying `Pending`.

> [!NOTE]
> A rootfs can't add `/dev/kvm`. CPU virtualization comes from the hypervisor, not the disk image. iximiuz Labs' `cloud-hypervisor` backend, which did support nested virtualization, has been disabled since July 13, 2026.

### SELinux mounted with no policy

The playground kernel mounts `/sys/fs/selinux`, but no SELinux policy is loaded. KubeVirt treats SELinux as active whenever `/sys/fs/selinux/enforce` exists, and tries to read the SELinux label of each VM's QEMU process to set up its network. The kernel refuses, and every VM crashes:

```
failed to configure vmi network: setup failed, err: Critical network error:
could not retrieve pid 22479 selinux label: getxattr /proc/22479/attr/current: operation not supported
```

`selinuxfs-unmount.service` runs on `cplane-01`, `node-01`, and `node-02` before K3s on every boot. It unmounts `/sys/fs/selinux` only in that exact state: mounted, with PID 1 still labeled `kernel` (no policy). KubeVirt then sees SELinux as disabled and VMs start normally.

## VM screen in the browser

`vm-vnc` shows a VM's graphical console in a browser tab, with no VNC client needed. It's installed on `dev-machine` and `cplane-01`.

```bash
vm-vnc testvm
```

Then open the playground's **VM Screen** tab (port `6080` on `dev-machine`). Press `Ctrl+C` to stop.

| Part | Role |
|---|---|
| `virtctl vnc <vm> --proxy-only --port 5900` | Connects to the VM's VNC console through the Kubernetes API, on `127.0.0.1:5900` |
| `websockify` (Ubuntu package) | Bridges that VNC port to a WebSocket and serves noVNC on `0.0.0.0:6080` |
| `novnc` (Ubuntu package) | The browser VNC client in `/usr/share/novnc` |
| `index.html` | Opens `vnc.html` with autoconnect, scaling, and reconnect turned on |

`vm-vnc` restarts the `virtctl` proxy whenever it exits, so reloading the tab reconnects. `Ctrl+C` stops the proxy and websockify together.

| Option | Example | Effect |
|---|---|---|
| Namespace | `vm-vnc myvm my-namespace` | VM in another namespace (default `default`) |
| `WEB_PORT` | `WEB_PORT=6081 vm-vnc myvm` | Browser port. Change the tab in `manifest.yaml` to match. |
| `VNC_PORT` | `VNC_PORT=5901 vm-vnc myvm` | Local port between `virtctl` and websockify |

> [!NOTE]
> The VNC console shows the VM's own screen. Cloud images such as CirrOS, Ubuntu, and AlmaLinux have no desktop, so you see a text login. A graphical login needs a desktop and display manager inside the guest.

On `cplane-01` there is no tab for port 6080. Use the playground's port exposing option on `cplane-01` with port `6080` instead.

## Terminal

Every machine gets the same terminal layout as the Rust and OpenTofu playgrounds, with the **Tokyo Night** theme, from `terminal/setup.sh`. zsh is the default shell for `laborant` and `root`, and bash still works with a plain starship prompt.

| Tool | Version | Purpose |
|---|---|---|
| starship | 1.26.0 | Prompt: host, folder, git, **Kubernetes context (namespace)**, time, command duration, exit status |
| eza | 0.23.5 | `ls`, `ll`, `tree` |
| bat | 0.26.1 | `cat` with syntax highlighting (built-in `Tokyo Night` theme), also used for man pages and `git diff` |
| fd | 10.5.0 | File search, used by fzf |
| zoxide | 0.10.0 | `z <folder>` jumps to frequent folders |
| atuin | 18.22.0 | `Ctrl+R` history search |
| delta | 0.19.2 | `git diff` pager |
| lazygit | 0.65.1 | `lg` |
| fastfetch | 2.68.1 | System info at login: K3s and Docker versions, KubeVirt version and phase, running VM count |
| zsh-autosuggestions, zsh-syntax-highlighting | Ubuntu packages | Suggestions and highlighting while typing |
| tmux | Ubuntu package | Tokyo Night status bar |

Shell completion is set up for whichever of `kubectl` (and `k`), `helm`, `virtctl`, `crane`, and `docker` the machine has.

Icons need a Nerd Font on the machine that draws the terminal, which browser tabs can't load. So the prompt starts in plain mode (`/etc/starship-plain.toml`, colored blocks only). Over `labctl ssh` from Ghostty, Kitty, or WezTerm, icons turn on automatically. Run `icons on` or `icons off` to switch, and the choice is remembered.

The Kubernetes prompt segment only appears where a kubeconfig exists: `dev-machine` and `cplane-01`. K3s agents have none, so `node-01` and `node-02` show a prompt without it.

## Build locally

Build one target at a time:

```bash
docker build --target cplane -t ghcr.io/omkar-shelke25/kubevirt-playground:cplane 300-rootfs-kubevirt
```

```bash
docker build --target node -t ghcr.io/omkar-shelke25/kubevirt-playground:node 300-rootfs-kubevirt
```

```bash
docker build --target dev-machine -t ghcr.io/omkar-shelke25/kubevirt-playground:dev-machine 300-rootfs-kubevirt
```

Build arguments:

| Argument | Default | Effect |
|---|---|---|
| `KUBEVIRT_VERSION` | `v1.9.0` | KubeVirt, virtctl, and preloaded image version |
| `CDI_VERSION` | `v1.66.1` | CDI version |
| `KUBEVIRT_MANAGER_VERSION` | `1.5.4` | KubeVirt Manager manifest and image version |
| `KUBEVIRT_MANAGER_NODEPORT` | `30080` | NodePort for the web UI. Change the tab in `manifest.yaml` to match. |
| `PRELOAD_IMAGES` | `true` | `false` skips image preloading. Images get much smaller, but the first boot waits on downloads. |
| `STARSHIP_VERSION`, `EZA_VERSION`, `BAT_VERSION`, `FD_VERSION`, `ZOXIDE_VERSION`, `DELTA_VERSION`, `ATUIN_VERSION`, `LAZYGIT_VERSION`, `FASTFETCH_VERSION` | See the Terminal table | Terminal tool versions |
| `CPLANE_BASE`, `NODE_BASE`, `DEV_BASE`, `BUILDER_BASE` | Official iximiuz rootfs images | Base images, for example to pin a specific iximiuz release |

## Publish

Pushing to `main` with changes under `300-rootfs-kubevirt/` runs `.github/workflows/build-rootfs.yml`. It builds the three targets in parallel and pushes three tags for each:

| Tag | Example |
|---|---|
| Target | `ghcr.io/omkar-shelke25/kubevirt-playground:cplane` |
| Target and KubeVirt version | `ghcr.io/omkar-shelke25/kubevirt-playground:cplane-v1.9.0` |
| Target and commit | `ghcr.io/omkar-shelke25/kubevirt-playground:cplane-sha-<commit>` |

> [!IMPORTANT]
> iximiuz Labs can only pull public images. After the first push, open the package settings on GitHub and change its visibility to **Public**.

## Create the playground

```bash
labctl playground create kubevirt-k3s --base flexbox -f 300-rootfs-kubevirt/manifest.yaml
```

`labctl` prints the full playground name with a suffix, for example `kubevirt-k3s-1a2b3c4d`. Start it:

```bash
labctl playground start kubevirt-k3s-1a2b3c4d --open
```

Four init tasks run on `dev-machine` before the playground opens. The last three wait for `init_wait_nodes` and then run in parallel:

| Task | Waits until |
|---|---|
| `init_wait_nodes` | All 3 K3s nodes are `Ready` |
| `init_wait_kubevirt` | KubeVirt is `Available` |
| `init_wait_cdi` | CDI is `Available` |
| `init_wait_kubevirt_manager` | The KubeVirt Manager Deployment is rolled out |

| Machine | CPU / RAM | Disk |
|---|---|---|
| `dev-machine` | 2 vCPU / 4 GiB | 30 GiB |
| `cplane-01` | 4 vCPU / 4 GiB | 30 GiB |
| `node-01`, `node-02` | 2 vCPU / 4 GiB each | 30 GiB each |

> [!WARNING]
> That's 10 vCPU and 16 GiB in total, which needs a paid plan. On the free plan (5 vCPU / 8 GiB per playground), iximiuz Labs scales every machine down to about half, so each node gets about 2 GiB. Stick to the CirrOS test VM there.

## Verify

On `dev-machine`:

```bash
kubectl get nodes
```

`cplane-01`, `node-01`, and `node-02` are all `Ready`.

```bash
kubectl -n kubevirt get pods -o wide
```

`virt-operator`, `virt-api`, and `virt-controller` run on `cplane-01`, and there is one `virt-handler` on each node. Check CDI and the web UI the same way with `kubectl -n cdi get pods -o wide` and `kubectl -n kubevirt-manager get pods -o wide`: both run on `cplane-01`.

Start the test VM and check which node it runs on:

```bash
kubectl apply -f ~/testvm.yaml
```

```bash
virtctl start testvm
```

```bash
kubectl wait vmi testvm --for=condition=Ready --timeout=5m
```

```bash
kubectl get vmi testvm -o wide
```

```bash
virtctl console testvm
```

Log in as `cirros` with password `gocubsgo`. Press `Ctrl+]` to leave.

Check CDI and the default StorageClass:

```bash
kubectl get cdi cdi
```

```bash
kubectl get storageclass
```

`local-path` is marked `(default)`.

Open the **KubeVirt Manager** tab. `testvm` is listed, and its VNC console opens in the browser.

On `cplane-01`, `node-01`, or `node-02`, check the SELinux workaround:

```bash
journalctl -u selinuxfs-unmount --no-pager
```

You should see `selinuxfs unmounted (no SELinux policy loaded)`.

## Troubleshooting

| Symptom | Check |
|---|---|
| Playground start times out on `init_wait_nodes` | On the stuck node: `sudo journalctl -u k3s-agent -f`. Agents join `https://172.16.0.2:6443`, so `cplane-01` must keep that IP. |
| Playground start times out on `init_wait_kubevirt` | `kubectl -n kubevirt get pods -o wide`. A `Pending` pod usually means not enough memory. |
| KubeVirt not installed at all | `kubectl get addons -n kube-system` lists the files K3s applied from its manifests folder, with any errors |
| `kubectl` on `dev-machine` says connection refused | The kubeconfig copy from `cplane-01` hasn't finished. Check `sudo systemctl status kubeconfig-setup`. |
| VM crashes a few seconds after start | On that VM's node: `systemctl status selinuxfs-unmount` and `grep selinuxfs /proc/mounts`. If still mounted, run `sudo umount /sys/fs/selinux`. |
| VM stuck `Pending` with `Insufficient devices.kubevirt.io/kvm` | Emulation is off. `kubectl -n kubevirt get kubevirt kubevirt -o yaml \| grep useEmulation` |
| Images pulled at runtime despite preloading | Check the build log for `WARNING: could not preload` |
| Playground start times out on `init_wait_cdi` | `kubectl -n cdi get pods -o wide`. CDI pods are pinned to `cplane-01`, so a full `cplane-01` blocks them. |
| KubeVirt Manager tab shows an error | `kubectl -n kubevirt-manager get pods,svc`. The Service must be NodePort `30080`. |
| KubeVirt Manager says `CDI (Containerized Data Importer) not found!` | CDI isn't `Available` yet. `kubectl get cdi cdi` |
| VM Screen tab shows `Failed to connect to server` | `vm-vnc` isn't running. Run `vm-vnc <vm>` on `dev-machine` and reload the tab. |
| `vm-vnc` says the proxy didn't start | It prints `virtctl`'s output. Usually the VM isn't running: `virtctl start <vm>` |
| A DataVolume stays `Pending` | `local-path` creates the disk only once a VM using it is scheduled. Start the VM. |

> [!NOTE]
> K3s owns the objects it applies from its manifests folder. If you change the KubeVirt CR with `kubectl`, K3s may restore the file's version on its next restart. To change it permanently, edit `kubevirt/20-kubevirt-cr.yaml` and rebuild.

## Upgrade versions

Change `KUBEVIRT_VERSION` in `.github/workflows/build-rootfs.yml` and push. All three images pick up the new operator manifest, `virtctl`, preloaded images, and test VM disk tag. `CDI_VERSION` and `KUBEVIRT_MANAGER_VERSION` work the same way, from the same `env` block.
