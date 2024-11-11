# Local copy of key_pair
resource "local_file" "key" {
  content  = tls_private_key.foo.private_key_pem
  filename = "${aws_key_pair.foo.key_name}.pem"
}

resource "null_resource" "set_readonly" {
  provisioner "local-exec" {
    command = "chmod 400 ${local_file.key.filename}"
  }

  triggers = {
    key_file = local_file.key.filename
  }
}

# resource "null_resource" "create_local_directory" {
#   provisioner "local-exec" {
#     command = "mkdir -p /home/ubuntu/Desktop/k8s/k8s-user-files"
#   }
# }