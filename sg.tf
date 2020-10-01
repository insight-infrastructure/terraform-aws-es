
data "aws_vpc" "default" {
  default = true
}

data "aws_subnet_ids" "default" {
  vpc_id = data.aws_vpc.default.id
}

data "aws_subnet" "default" {
  count = length(data.aws_subnet_ids.default.ids)
  id    = tolist(data.aws_subnet_ids.default.ids)[count.index]
}

locals {
  subnet_ids = var.subnet_ids == "" ? values(zipmap(data.aws_subnet.default.*.availability_zone, data.aws_subnet.default.*.id)) : var.subnet_ids
}

resource "aws_security_group" "this" {
  count       = 1
  vpc_id      = var.vpc_id == "" ? data.aws_vpc.default.id : var.vpc_id
  name        = var.id
  description = "Allow inbound traffic from Security Groups and CIDRs. Allow all outbound traffic"
  tags        = var.tags
}

resource "aws_security_group_rule" "public_ports" {
  count             = length(var.public_ports)
  description       = "Allow inbound traffic from public"
  type              = "ingress"
  from_port         = var.public_ports[count.index]
  to_port           = var.public_ports[count.index]
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = join("", aws_security_group.this.*.id)
}

resource "aws_security_group_rule" "private_ports" {
  count             = length(var.private_ports)
  description       = "Allow inbound traffic from CIDR blocks"
  type              = "ingress"
  from_port         = var.private_ports[count.index]
  to_port           = var.private_ports[count.index]
  protocol          = "tcp"
  cidr_blocks       = var.allowed_cidr_blocks
  security_group_id = join("", aws_security_group.this.*.id)
}

resource "aws_security_group_rule" "egress" {
  count             = 1
  description       = "Allow all egress traffic"
  type              = "egress"
  from_port         = 0
  to_port           = 65535
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = join("", aws_security_group.this.*.id)
}

