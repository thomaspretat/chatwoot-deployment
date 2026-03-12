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
    use_proxy       = false
    extra_arguments = [
      "--extra-vars", "gitlab_registry_user=${var.gitlab_registry_user} gitlab_registry_token=${var.gitlab_registry_token}"
    ]
  }
  post-processor "amazon-ami-management" {
    regions       = ["eu-west-3"]
    identifier    = "chatwoot"
    keep_releases = 1
  }
}
