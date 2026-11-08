# Customize the Ubuntu 24.04 cloud image with the Packer QEMU builder, then
# deploy it to KubeVirt.
#
#   cd ~/packer/ubuntu
#   packer init .
#   packer build .
#   MEMORY=1Gi vm-image deploy output-ubuntu/ubuntu-custom.qcow2
#
# There is no /dev/kvm in a playground, so QEMU uses software emulation
# (accelerator = "tcg"). Expect 10 to 20 minutes for this build, and a few
# minutes for each boot of the VM. Start with the CirrOS template to see the
# workflow in minutes.

packer {
  required_plugins {
    qemu = {
      source  = "github.com/hashicorp/qemu"
      version = ">= 1.1.8"
    }
  }
}

source "qemu" "ubuntu" {
  iso_url      = "https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img"
  iso_checksum = "file:https://cloud-images.ubuntu.com/noble/current/SHA256SUMS"
  disk_image   = true
  disk_size    = "6G"

  output_directory = "output-ubuntu"
  vm_name          = "ubuntu-custom.qcow2"
  format           = "qcow2"

  accelerator    = "tcg"
  headless       = true
  cpus           = 2
  memory         = 1536
  net_device     = "virtio-net"
  disk_interface = "virtio"

  # NoCloud seed: creates the user Packer logs in as.
  cd_label = "cidata"
  cd_files = ["./cloud-init/user-data", "./cloud-init/meta-data"]

  communicator     = "ssh"
  ssh_username     = "packer"
  ssh_password     = "packer"
  ssh_timeout      = "40m"
  shutdown_command = "sudo shutdown -P now"
}

build {
  sources = ["source.qemu.ubuntu"]

  provisioner "shell" {
    inline = [
      "cloud-init status --wait || true",
      "sudo apt-get update",
      "sudo apt-get install -y --no-install-recommends nginx",
      "sudo systemctl enable nginx",
      # Let cloud-init run again on first boot in KubeVirt.
      "sudo cloud-init clean --logs",
    ]
  }
}
