resource "aws_vpc" "lab" {
  cidr_block           = "10.42.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = { Name = var.name
  }
}
resource "aws_subnet" "public" {
  count                   = 2
  vpc_id                  = aws_vpc.lab.id
  cidr_block              = cidrsubnet(aws_vpc.lab.cidr_block, 8, count.index)
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = false
  tags = { Name = "${var.name}-public-${count.index}"
  }
}
resource "aws_subnet" "private" {
  count             = 2
  vpc_id            = aws_vpc.lab.id
  cidr_block        = cidrsubnet(aws_vpc.lab.cidr_block, 8, count.index + 10)
  availability_zone = data.aws_availability_zones.available.names[count.index]
  tags = { Name = "${var.name}-private-${count.index}"
  }
}
resource "aws_internet_gateway" "lab" {
  vpc_id = aws_vpc.lab.id
}
resource "aws_eip" "nat" {
  domain = "vpc"
}
resource "aws_nat_gateway" "lab" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[0].id
  depends_on    = [aws_internet_gateway.lab]
}
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.lab.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.lab.id
  }
}
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.lab.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.lab.id
  }
}
resource "aws_route_table_association" "public" {
  count          = 2
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}
resource "aws_route_table_association" "private" {
  count          = 2
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}
resource "aws_security_group" "alb" {
  name_prefix = "${var.name}-alb-"
  vpc_id      = aws_vpc.lab.id
}
resource "aws_security_group" "app" {
  for_each    = local.services
  name_prefix = "${var.name}-${each.key}-"
  vpc_id      = aws_vpc.lab.id
}
resource "aws_security_group" "redis" {
  name_prefix = "${var.name}-redis-"
  vpc_id      = aws_vpc.lab.id
}
resource "aws_security_group" "db" {
  name_prefix = "${var.name}-db-"
  vpc_id      = aws_vpc.lab.id
}
resource "aws_vpc_security_group_ingress_rule" "https" {
  security_group_id = aws_security_group.alb.id
  cidr_ipv4         = var.allowed_ingress_cidr
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
}
resource "aws_vpc_security_group_egress_rule" "alb_to_a" {
  security_group_id            = aws_security_group.alb.id
  referenced_security_group_id = aws_security_group.app["service-a"].id
  from_port                    = 8080
  to_port                      = 8080
  ip_protocol                  = "tcp"
}
resource "aws_vpc_security_group_ingress_rule" "a_from_alb" {
  security_group_id            = aws_security_group.app["service-a"].id
  referenced_security_group_id = aws_security_group.alb.id
  from_port                    = 8080
  to_port                      = 8080
  ip_protocol                  = "tcp"
}
resource "aws_vpc_security_group_ingress_rule" "b_from_clients" {
  for_each                     = toset(["service-a", "worker"])
  security_group_id            = aws_security_group.app["service-b"].id
  referenced_security_group_id = aws_security_group.app[each.key].id
  from_port                    = 8081
  to_port                      = 8081
  ip_protocol                  = "tcp"
}
resource "aws_vpc_security_group_ingress_rule" "redis_from_clients" {
  for_each                     = toset(["service-a", "worker"])
  security_group_id            = aws_security_group.redis.id
  referenced_security_group_id = aws_security_group.app[each.key].id
  from_port                    = 6379
  to_port                      = 6379
  ip_protocol                  = "tcp"
}
resource "aws_vpc_security_group_ingress_rule" "db_from_apps" {
  for_each                     = local.services
  security_group_id            = aws_security_group.db.id
  referenced_security_group_id = aws_security_group.app[each.key].id
  from_port                    = 5432
  to_port                      = 5432
  ip_protocol                  = "tcp"
}
# HTTPS para AWS APIs/ECR via NAT; DNS VPC não é filtrável por security groups.
resource "aws_vpc_security_group_egress_rule" "https_from_apps" {
  for_each          = local.services
  security_group_id = aws_security_group.app[each.key].id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
}
resource "aws_vpc_security_group_egress_rule" "db_from_apps" {
  for_each                     = local.services
  security_group_id            = aws_security_group.app[each.key].id
  referenced_security_group_id = aws_security_group.db.id
  from_port                    = 5432
  to_port                      = 5432
  ip_protocol                  = "tcp"
}
resource "aws_vpc_security_group_egress_rule" "b_from_clients" {
  for_each                     = toset(["service-a", "worker"])
  security_group_id            = aws_security_group.app[each.key].id
  referenced_security_group_id = aws_security_group.app["service-b"].id
  from_port                    = 8081
  to_port                      = 8081
  ip_protocol                  = "tcp"
}
resource "aws_vpc_security_group_egress_rule" "redis_from_clients" {
  for_each                     = toset(["service-a", "worker"])
  security_group_id            = aws_security_group.app[each.key].id
  referenced_security_group_id = aws_security_group.redis.id
  from_port                    = 6379
  to_port                      = 6379
  ip_protocol                  = "tcp"
}
resource "aws_service_discovery_private_dns_namespace" "lab" {
  name = "${var.name}.local"
  vpc  = aws_vpc.lab.id
}
resource "aws_service_discovery_service" "b" {
  name = "service-b"
  dns_config {
    namespace_id = aws_service_discovery_private_dns_namespace.lab.id
    dns_records {
      ttl  = 10
      type = "A"
    }
    routing_policy = "MULTIVALUE"

  }
  health_check_custom_config {}
}
