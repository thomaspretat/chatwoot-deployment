resource "aws_instance" "bastion" {
  count                  = var.instance_count
  ami                    = var.ami_id
  instance_type          = var.instance_type
  key_name               = var.key_name
  subnet_id              = var.subnet_id
  vpc_security_group_ids = [var.security_group_id]

  associate_public_ip_address = true

  root_block_device {
    volume_type           = "gp3"
    volume_size           = 20
    delete_on_termination = true
    encrypted             = true
  }

  tags = merge(var.tags, { Name = "chatwoot-${var.env}-bastion-${count.index + 1}" })
}

resource "aws_eip" "bastion" {
  count    = var.instance_count
  instance = aws_instance.bastion[count.index].id
  domain   = "vpc"
  tags     = merge(var.tags, { Name = "chatwoot-${var.env}-bastion-eip-${count.index + 1}" })
}
