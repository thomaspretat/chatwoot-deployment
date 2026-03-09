# packer/chatwoot.pkr.hcl

source "amazon-ebs" "chatwoot" {
  ami_name      = "chatwoot-{{timestamp}}"
  instance_type = "t3.small"
  source_ami    = data.amazon-ami.ubuntu.id
  ssh_username  = "ubuntu"
  region        = "eu-west-3"
}

build {
  sources = ["source.amazon-ebs.chatwoot"]
  provisioner "ansible" {
    playbook_file = "../ansible/chatwoot-playbook.yml"
  }
}
