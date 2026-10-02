#!/bin/sh
#
# Pulls images as tarballs at build time. K3s imports every tarball in
# /var/lib/rancher/k3s/agent/images at boot, so nodes start without downloads.
#
# Each image is pulled once into a pool, then hard-linked into the folder of
# every node role that needs it. A failed pull only prints a warning: that
# image is then pulled at runtime instead.
#
# Usage: CPLANE_IMAGES="<ref> ..." NODE_IMAGES="<ref> ..." preload-images.sh <out-dir>
set -u

out="$1"
pool="${out}/pool"
mkdir -p "$pool" "${out}/cplane" "${out}/node"

# quay.io/kubevirt/virt-api:v1.9.0 -> preload-virt-api.tar
tarball() {
  name="${1##*/}"
  echo "preload-${name%%:*}.tar"
}

for ref in $CPLANE_IMAGES $NODE_IMAGES; do
  file="${pool}/$(tarball "$ref")"
  [ -f "$file" ] && continue
  if crane pull --platform linux/amd64 "$ref" "$file"; then
    echo "preloaded ${ref}"
  else
    rm -f "$file"
    echo "WARNING: could not preload ${ref}, it will be pulled at runtime"
  fi
done

for ref in $CPLANE_IMAGES; do
  file="$(tarball "$ref")"
  [ -f "${pool}/${file}" ] && ln "${pool}/${file}" "${out}/cplane/${file}"
done
for ref in $NODE_IMAGES; do
  file="$(tarball "$ref")"
  [ -f "${pool}/${file}" ] && ln "${pool}/${file}" "${out}/node/${file}"
done

rm -rf "$pool"
