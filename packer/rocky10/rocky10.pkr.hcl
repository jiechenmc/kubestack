# rocky linux 10 vm image for kubevirt: rocky's GenericCloud qcow2, updated, qemu-guest-agent enabled,
# cloud-init reset so every vm made from it runs cloud-init fresh (default user "rocky", keys from
# the vm's cloudInitNoCloud volume).
#
#   cd packer/rocky10 && packer init . && packer build .
#   virtctl image-upload dv rocky-10 -n vm-images --size=20Gi --image-path=output/rocky-10.qcow2 \
#     --storage-class=rook-ceph-block --access-mode=ReadWriteOnce --volume-mode=block --force-bind
#
# builds on this host under kvm; vms then clone the vm-images/rocky-10 DataVolume as their root disk

packer {
  required_plugins {
    qemu = {
      source  = "github.com/hashicorp/qemu"
      version = "1.1.8"
    }
  }
}

variable "rocky_release" {
  type        = string
  description = "GenericCloud-Base build from https://dl.rockylinux.org/pub/rocky/10/images/x86_64/"
  default     = "10.2-20260525.0"
}

locals {
  base_url = "https://dl.rockylinux.org/pub/rocky/10/images/x86_64/Rocky-10-GenericCloud-Base-${var.rocky_release}.x86_64.qcow2"
  # throwaway login for the build only; the packer user is deleted before the image is saved
  ssh_password = uuidv4()
}

source "qemu" "rocky10" {
  iso_url          = local.base_url
  iso_checksum     = "file:${local.base_url}.CHECKSUM"
  disk_image       = true
  use_backing_file = false
  disk_size        = "10G"
  format           = "qcow2"
  disk_compression = true
  disk_interface   = "virtio"
  disk_discard     = "unmap" # fstrim in the guest frees blocks, so the compressed image stays small

  qemu_binary  = "/usr/libexec/qemu-kvm"
  accelerator  = "kvm"
  machine_type = "q35"
  # rocky 10 needs x86-64-v3; qemu's default cpu model doesn't boot it
  cpu_model = "host"
  cpus      = 2
  memory    = 2048
  headless  = true

  # NoCloud seed: a build-only sudo user with a password packer can ssh in with
  cd_label = "cidata"
  cd_content = {
    "meta-data" = "instance-id: packer-rocky10\n"
    "user-data" = <<-EOT
      #cloud-config
      ssh_pwauth: true
      users:
        - name: packer
          sudo: ALL=(ALL) NOPASSWD:ALL
          lock_passwd: false
          plain_text_passwd: ${local.ssh_password}
    EOT
  }

  communicator = "ssh"
  ssh_username = "packer"
  ssh_password = local.ssh_password
  ssh_timeout  = "10m"

  # last step, as root: drop the build user and everything cloud-init did for this boot, so the image
  # boots like a fresh GenericCloud one (new machine-id, host keys and default user per vm).
  # userdel -f warns that the ssh session still uses the packer user, then deletes it anyway
  shutdown_command = "sudo sh -c 'rm -f /etc/sudoers.d/90-cloud-init-users /etc/ssh/sshd_config.d/50-cloud-init.conf /etc/ssh/ssh_host_*; cloud-init clean --logs --seed --machine-id; userdel -rf packer; shutdown -P now'"

  output_directory = "output"
  vm_name          = "rocky-10.qcow2"
}

build {
  sources = ["source.qemu.rocky10"]

  provisioner "shell" {
    execute_command = "sudo sh -eux '{{ .Path }}'"
    inline = [
      "dnf -y upgrade",
      # lets kubevirt report the vm's ips, os and logged-in users, and freeze filesystems for snapshots
      "dnf -y install qemu-guest-agent",
      "systemctl enable qemu-guest-agent",
      "dnf clean all",
      "fstrim -av",
    ]
  }
}
