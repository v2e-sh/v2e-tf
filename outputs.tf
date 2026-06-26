locals {
  wan_ip = var.wan_address == "dhcp" ? "<vyos-wan-dhcp-ip>" : split("/", var.wan_address)[0]
}

output "router_gateways" {
  description = "VyOS gateway IP in each subnet."
  value       = { for v in local.vlans : v.name => v.gateway_cidr }
}

output "node_addresses" {
  description = "Static IPs of the three nodes."
  value       = local.node_ip
}

output "ssh_to_vyos" {
  description = "Manage the router directly (mac is on the WAN segment)."
  value       = "ssh ${var.router_user}@${local.wan_ip}"
}

output "ssh_to_control" {
  description = "Reach the control node from your mac via the VyOS WAN port-forward."
  value       = "ssh -p ${var.control_ssh_wan_port} ${var.cluster_user}@${local.wan_ip}"
}

output "mesh_v2e" {
  description = "Primary mesh: the primary user on control reaches all nodes."
  value       = [for tk, tn in local.nodes : "ssh ${tk}  (=> ${var.cluster_user}@${local.node_ip[tk]})" if tk != "control"]
}

output "mesh_agent" {
  description = "Agent mesh: the agent user on the agent node reaches all nodes."
  value       = [for tk, tn in local.nodes : "ssh ${tk}  (=> ${var.agent_user}@${local.node_ip[tk]})" if tk != "agent"]
}

output "primary_public_key" {
  description = "Public key for the primary mesh (private key lives on control)."
  value       = local.meshes["primary"].public
}

output "agent_public_key" {
  description = "Public key for the agent mesh (private key lives on the agent node)."
  value       = local.meshes["agent"].public
}
