# Customize the CirrOS cloud image with the Packer QEMU builder, then deploy it
# to KubeVirt.
#
#   cd ~/packer/cirros
#   packer init .
#   packer build .
#   vm-image deploy output-cirros/cirros-custom.qcow2
#
# Playground machines have no /dev/kvm, so QEMU runs with software emulation
# (accelerator = "tcg"). CirrOS is tiny, so the build takes a few minutes. On a
# host with KVM, change the accelerator to "kvm" for a much faster build.

packer {
  required_plugins {
    qemu = {
      source  = "github.com/hashicorp/qemu"
      version = ">= 1.1.8"
    }
  }
}

variable "cirros_version" {
  type    = string
  default = "0.6.3"
}

variable "cirros_sha256" {
  type    = string
  default = "7d6355852aeb6dbcd191bcda7cd74f1536cfe5cbf8a10495a7283a8396e4b75b"
}

source "qemu" "cirros" {
  # disk_image = true boots this image instead of installing from an ISO.
  iso_url      = "https://github.com/cirros-dev/cirros/releases/download/${var.cirros_version}/cirros-${var.cirros_version}-x86_64-disk.img"
  iso_checksum = "sha256:${var.cirros_sha256}"
  disk_image   = true
  disk_size    = "1G" # Packer would grow the disk to 40G by default

  output_directory = "output-cirros"
  vm_name          = "cirros-custom.qcow2"
  format           = "qcow2"

  accelerator    = "tcg"
  headless       = true
  cpus           = 2
  memory         = 512
  net_device     = "virtio-net"
  disk_interface = "virtio"

  # A NoCloud seed disk, so CirrOS does not wait for a metadata service.
  # CirrOS reads meta-data as JSON.
  cd_label = "cidata"
  cd_files = ["./seed/user-data", "./seed/meta-data"]

  communicator     = "ssh"
  ssh_username     = "cirros"
  ssh_password     = "gocubsgo"
  ssh_timeout      = "15m"
  shutdown_command = "sudo poweroff"
}

build {
  sources = ["source.qemu.cirros"]

  # Leave a marker in the image, so you can see your change after deploying.
  provisioner "shell" {
    inline = [
      "echo \"built with Packer on $(date -u +%FT%TZ)\" > /home/cirros/built-by-packer.txt",
      "cat /home/cirros/built-by-packer.txt",
    ]
  }
}
