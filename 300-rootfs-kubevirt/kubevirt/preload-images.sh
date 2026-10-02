#!/bin/sh
#
# Pulls KubeVirt images as tarballs at build time. K3s imports every tarball in
# /var/lib/rancher/k3s/agent/images at boot, so nodes start without downloads.
#
# Each image is pulled once into a pool, then hard-linked into the folder of
# every node role that needs it. A failed pull only prints a warning: that
# image is then pulled at runtime instead.
#
# Usage: preload-images.sh <kubevirt-version> <out-dir>
set -u

version="$1"
out="$2"
pool="${out}/pool"
mkdir -p "$pool" "${out}/cplane" "${out}/node"

# KubeVirt control plane pods are pinned to control plane nodes by the
# operator, so only cplane needs them. Every node can run VMs.
cplane_images="virt-operator virt-api virt-controller virt-exportproxy virt-handler virt-launcher cirros-container-disk-demo"
node_images="virt-handler virt-launcher cirros-container-disk-demo"

for image in $cplane_images; do
  if crane pull --platform linux/amd64 "quay.io/kubevirt/${image}:${version}" "${pool}/kubevirt-${image}.tar"; then
    echo "preloaded ${image}"
  else
    echo "WARNING: could not preload ${image}, it will be pulled at runtime"
  fi
done

for role in cplane node; do
  if [ "$role" = cplane ]; then images=$cplane_images; else images=$node_images; fi
  for image in $images; do
    if [ -f "${pool}/kubevirt-${image}.tar" ]; then
      ln "${pool}/kubevirt-${image}.tar" "${out}/${role}/kubevirt-${image}.tar"
    fi
  done
done

rm -rf "$pool"
