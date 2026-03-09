# packer/bastion.pkr.hcl

source "amazon-ebs" "bastion" {
  ami_name      = "bastion-{{timestamp}}"
  instance_type = "t3.small"
  source_ami    = data.amazon-ami.ubuntu.id
  ssh_username  = "ubuntu"
  region        = "eu-west-3"
}

build {
  sources = ["source.amazon-ebs.bastion"]
  provisioner "ansible" {
    playbook_file = "../ansible/bastion-playbook.yml"
  }
}
