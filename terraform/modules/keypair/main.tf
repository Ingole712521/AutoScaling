resource "tls_private_key" "this" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "this" {
  key_name   = var.key_pair_name
  public_key = tls_private_key.this.public_key_openssh
}

resource "local_file" "private_key" {
  count           = var.create_local_private_key_file ? 1 : 0
  content         = tls_private_key.this.private_key_pem
  filename        = "${path.root}/${var.key_pair_name}.pem"
  file_permission = "0400"
}
