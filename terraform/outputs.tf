output "node_ips" {
  description = "Node name => IP address"
  value       = { for name, node in var.nodes : name => split("/", node.ip)[0] }
}
