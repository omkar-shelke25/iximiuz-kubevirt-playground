# Build a container image with the Packer Docker builder, using the Docker
# engine on this machine.
#
#   cd ~/packer/docker
#   packer init .
#   packer build .
#   docker run --rm packer-hello:1.0
#
# The same template language builds container images and VM images.

packer {
  required_plugins {
    docker = {
      source  = "github.com/hashicorp/docker"
      version = ">= 1.1.5"
    }
  }
}

source "docker" "alpine" {
  image  = "alpine:3"
  commit = true
  changes = [
    "CMD [\"cat\", \"/hello.txt\"]",
  ]
}

build {
  sources = ["source.docker.alpine"]

  provisioner "shell" {
    inline = [
      "echo 'hello from an image built with Packer' > /hello.txt",
    ]
  }

  post-processor "docker-tag" {
    repository = "packer-hello"
    tags       = ["1.0"]
  }
}
