# SSH trust meshes. One keypair per mesh user.
# - "primary" (user v2e): private key on the CONTROL node -> reaches all nodes.
# - "agent"   (user agent): private key on the AGENT node  -> reaches all nodes.
# Each mesh's PUBLIC key is authorized for that user on every node; the PRIVATE
# key is written only on the mesh's hub node.
resource "tls_private_key" "primary" {
  algorithm = "ED25519"
}

resource "tls_private_key" "agent" {
  algorithm = "ED25519"
}
