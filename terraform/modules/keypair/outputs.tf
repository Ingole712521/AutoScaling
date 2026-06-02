output "key_name" {
  value = aws_key_pair.this.key_name
}

output "private_key_path" {
  value = var.create_local_private_key_file ? local_file.private_key[0].filename : null
}
