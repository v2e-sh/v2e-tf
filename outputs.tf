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
  description = "How to reach the VyOS router as the bootstrap 'vyos' user. Direct WAN SSH only when the firewall is off OR trusted_mgmt_sources allows your IP; otherwise reach it via control. Phase-2 Ansible provisions dedicated router users."
  value = (
    !var.firewall_enabled || length(var.trusted_mgmt_sources) > 0
    ? "ssh ${local.router_bootstrap_user}@${local.wan_ip}"
    : "ssh -p ${var.control_ssh_wan_port} ${var.cluster_user}@${local.wan_ip}  =>  then on control: ssh vyos   (router WAN SSH is firewalled off; set trusted_mgmt_sources to open it)"
  )
}

output "ssh_to_control" {
  description = "Reach the control node from your mac via the VyOS WAN port-forward."
  value       = "ssh -p ${var.control_ssh_wan_port} ${var.cluster_user}@${local.wan_ip}"
}

output "mesh_v2e" {
  description = "Primary mesh: the v2e user on control reaches every node, plus the router as the bootstrap vyos user."
  value = concat(
    [for tk, tn in local.nodes : "ssh ${tk}  (=> ${var.cluster_user}@${local.node_ip[tk]})" if tk != "control"],
    ["ssh vyos  (=> ${local.router_bootstrap_user}@${local.node_gateway["control"]})"],
  )
}

output "mesh_ansible" {
  description = "Ansible mesh: the ansible user on control reaches every node, plus the router as the bootstrap vyos user."
  value = concat(
    [for tk, tn in local.nodes : "ssh ${tk}  (=> ${var.ansible_user}@${local.node_ip[tk]})" if tk != "control"],
    ["ssh vyos  (=> ${local.router_bootstrap_user}@${local.node_gateway["control"]})"],
  )
}

output "primary_public_key" {
  description = "Public key for the primary mesh (private key lives on control)."
  value       = local.meshes["primary"].public
}

output "ansible_public_key" {
  description = "Public key for the ansible mesh (private key lives on control)."
  value       = local.meshes["ansible"].public
}

output "cloudflare_tunnel_id" {
  description = "ID of the Cloudflare tunnel fronting control's SSH (null when disabled)."
  value       = one(cloudflare_zero_trust_tunnel_cloudflared.ssh[*].id)
}

output "cloudflared_tunnel_token" {
  description = "Connector run token (for Ansible / debugging; already injected into control's cloud-init)."
  value       = local.cloudflare_enabled ? one(data.cloudflare_zero_trust_tunnel_cloudflared_token.ssh[*].token) : null
  sensitive   = true
}

output "ssh_to_control_via_tunnel" {
  description = "Reach control via the Cloudflare tunnel (needs cloudflared + 'ProxyCommand cloudflared access ssh' on the mac)."
  value       = local.cloudflare_enabled ? "ssh ${var.cluster_user}@${var.tunnel_hostname}" : "cloudflare tunnel disabled — set cloudflare_api_token + account/zone IDs to enable"
}
