# packer/chatwoot.pkr.hcl

source "amazon-ebs" "chatwoot" {
  ami_name      = "chatwoot-{{timestamp}}"
  instance_type = "t3.small"
  source_ami    = data.amazon-ami.ubuntu.id
  ssh_username  = "ubuntu"
  region        = "eu-west-3"
  tags = {
    Amazon_AMI_Management_Identifier = "chatwoot"
  }
}

build {
  sources = ["source.amazon-ebs.chatwoot"]
  provisioner "ansible" {
    playbook_file   = "../ansible/chatwoot-playbook.yml"
    extra_arguments = ["--become"]
  }
  post-processor "amazon-ami-management" {
    regions       = ["eu-west-3"]
    identifier    = "chatwoot"
    keep_releases = 1
  }
}
