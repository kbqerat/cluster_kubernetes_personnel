output "node_ips" {
  description = "Map of node name -> IPv4 address (populated once the VM has booted; run 'terraform refresh' if empty)."
  value = merge(
    { for s in multipass_instance.server : s.name => s.ipv4 },
    { for a in multipass_instance.agent : a.name => a.ipv4 },
  )
}

output "server_name" {
  value = multipass_instance.server[0].name
}

output "server_ip" {
  description = "IPv4 of the first k3s server node."
  value       = multipass_instance.server[0].ipv4
}

output "agent_names" {
  value = [for a in multipass_instance.agent : a.name]
}
