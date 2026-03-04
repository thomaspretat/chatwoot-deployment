# packer/bastion.pkr.hcl

# Installer le plugin Hashicorp nécessaire pour faire tourner Packer
packer {
  required_plugins {
    amazon = {
        version = ">= 1.2.0"
        source  = "github.com/hashicorp/amazon"
    }
  }
}

# Prendre une AMI de base Ubuntu préexistante sur le store
data "amazon-ami" "ubuntu" {
  filters = {
    name                = "ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"
    virtualization-type = "hvm"
  }
  owners      = ["099720109477"]
  most_recent = true
  region      = "eu-west-3"
}

# Créer notre nouvelle AMI en partant de la base ci-dessus
source "amazon-ebs" "bastion" {
  ami_name      = "bastion-{{timestamp}}"
  instance_type = "t3.micro"
  source_ami    = data.amazon-ami.ubuntu.id
  ssh_username  = "ubuntu"
  region        = "eu-west-3"
}

# Provisionner cette nouvelle AMI avec notre playbook
build {
  sources = ["source.amazon-ebs.bastion"]
  provisioner "ansible" {
    playbook_file = "../ansible/bastion-playbook.yml"
  }
}