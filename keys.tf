# SSH trust meshes. One keypair per mesh user.
# - "primary" (user v2e):     private key on CONTROL -> reaches all nodes + vyos.
# - "ansible" (user ansible): private key on CONTROL -> reaches all nodes + vyos.
# Each mesh's PUBLIC key is authorized for that user on every node (and on the
# router for the vyos user); the PRIVATE key is written only on the hub (control).
resource "tls_private_key" "primary" {
  algorithm = "ED25519"
}

resource "tls_private_key" "ansible" {
  algorithm = "ED25519"
}
