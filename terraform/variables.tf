variable "ssh_public_key" {
  description = "SSH public key injected into every node's 'ubuntu' user for k3sup access."
  type        = string
}

variable "node_image" {
  description = "Multipass image alias for every node."
  type        = string
  default     = "24.04"
}

# --- Server node(s) ---
variable "server_count" {
  description = "Number of k3s server (control-plane) nodes."
  type        = number
  default     = 1
}

variable "server_cpus" {
  type    = number
  default = 2
}

variable "server_memory" {
  type    = string
  default = "2GiB"
}

variable "server_disk" {
  type    = string
  default = "12GiB"
}

# --- Agent nodes ---
variable "agent_count" {
  description = "Number of k3s agent (worker) nodes."
  type        = number
  default     = 2
}

variable "agent_cpus" {
  type    = number
  default = 2
}

variable "agent_memory" {
  type    = string
  default = "2GiB"
}

variable "agent_disk" {
  type    = string
  default = "12GiB"
}
