# packer/monitoring.pkr.hcl

source "amazon-ebs" "monitoring" {
  ami_name      = "monitoring-{{timestamp}}"
  instance_type = "t3.small"
  source_ami    = data.amazon-ami.ubuntu.id
  ssh_username  = "ubuntu"
  region        = "eu-west-3"
  tags = {
    Amazon_AMI_Management_Identifier = "monitoring"
  }
}

build {
  sources = ["source.amazon-ebs.monitoring"]
  provisioner "ansible" {
    playbook_file   = "../ansible/monitoring-playbook.yml"
    extra_arguments = ["--become"]
  }
  post-processor "amazon-ami-management" {
    regions       = ["eu-west-3"]
    identifier    = "monitoring"
    keep_releases = 1
  }
}
