#!/bin/sh
#
# KubeVirt treats SELinux as active whenever /sys/fs/selinux/enforce exists.
# The iximiuz Labs kernel mounts selinuxfs but loads no SELinux policy, so when
# KubeVirt tries to read a process's SELinux label to set up a VM's network,
# the kernel answers "operation not supported" and the VM crashes.
#
# Unmount selinuxfs only in that exact state: mounted, with no policy loaded
# (PID 1 still has the "kernel" label). Real SELinux systems are left alone.

if [ ! -f /sys/fs/selinux/enforce ]; then
  echo "selinuxfs not mounted, nothing to do"
  exit 0
fi

label=$(tr -d '\0' < /proc/1/attr/current 2>/dev/null)
if [ "$label" != "kernel" ]; then
  echo "SELinux policy loaded (${label}), leaving selinuxfs mounted"
  exit 0
fi

umount /sys/fs/selinux && echo "selinuxfs unmounted (no SELinux policy loaded)"
