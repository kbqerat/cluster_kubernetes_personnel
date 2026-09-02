locals {
  cloud_init_rendered = templatefile("${path.module}/cloud-init/node.yaml.tftpl", {
    ssh_public_key = trimspace(var.ssh_public_key)
  })
  cloud_init_path = "${path.module}/.generated/node-cloud-init.yaml"
}

# Render the cloud-init file to disk so Multipass can consume it via --cloud-init.
resource "local_file" "cloud_init" {
  content              = local.cloud_init_rendered
  filename             = local.cloud_init_path
  file_permission      = "0600"
  directory_permission = "0700"
}

resource "multipass_instance" "server" {
  count = var.server_count

  name           = var.server_count > 1 ? "k3s-server-${count.index + 1}" : "k3s-server"
  image          = var.node_image
  cpus           = var.server_cpus
  memory         = var.server_memory
  disk           = var.server_disk
  cloudinit_file = local_file.cloud_init.filename

  depends_on = [local_file.cloud_init]
}

resource "multipass_instance" "agent" {
  count = var.agent_count

  name           = "k3s-agent-${count.index + 1}"
  image          = var.node_image
  cpus           = var.agent_cpus
  memory         = var.agent_memory
  disk           = var.agent_disk
  cloudinit_file = local_file.cloud_init.filename

  # Serialize creation after the server. Combined with `-parallelism=1` in the
  # Makefile this avoids the Multipass-on-macOS DHCP race that assigns the same
  # IP to VMs launched concurrently.
  depends_on = [local_file.cloud_init, multipass_instance.server]
}
