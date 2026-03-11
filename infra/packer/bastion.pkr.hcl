# packer/bastion.pkr.hcl

source "amazon-ebs" "bastion" {
  ami_name      = "bastion-{{timestamp}}"
  instance_type = "t3.small"
  source_ami    = data.amazon-ami.ubuntu.id
  ssh_username  = "ubuntu"
  region        = "eu-west-3"
  tags = {
    Amazon_AMI_Management_Identifier = "bastion"
  }
}

build {
  sources = ["source.amazon-ebs.bastion"]
  provisioner "ansible" {
    playbook_file = "../ansible/bastion-playbook.yml"
  }
  post-processor "amazon-ami-management" {
    regions       = ["eu-west-3"]
    identifier    = "bastion"
    keep_releases = 1
  }
}
