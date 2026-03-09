# packer/monitoring.pkr.hcl

source "amazon-ebs" "monitoring" {
  ami_name      = "monitoring-{{timestamp}}"
  instance_type = "t3.small"
  source_ami    = data.amazon-ami.ubuntu.id
  ssh_username  = "ubuntu"
  region        = "eu-west-3"
}

build {
  sources = ["source.amazon-ebs.monitoring"]
  provisioner "ansible" {
    playbook_file = "../ansible/monitoring-playbook.yml"
  }
}
