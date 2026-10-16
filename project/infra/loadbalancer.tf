resource "aws_lb" "api" {
  name                       = "${var.name}-api"
  internal                   = false
  load_balancer_type         = "application"
  security_groups            = [aws_security_group.alb.id]
  subnets                    = aws_subnet.public[*].id
  drop_invalid_header_fields = true
  enable_deletion_protection = var.deletion_protection
}
resource "aws_lb_target_group" "a" {
  name                 = "${var.name}-a"
  port                 = 8080
  protocol             = "HTTP"
  target_type          = "ip"
  vpc_id               = aws_vpc.lab.id
  deregistration_delay = 30
  health_check {
    path     = "/actuator/health"
    matcher  = "200"
    interval = 30
  }
}
resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.api.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = var.certificate_arn
  default_action {
    type = "fixed-response"
    fixed_response {
      content_type = "text/plain"
      message_body = "Rota não publicada"
      status_code  = "404"
    }

  }
}
resource "aws_lb_listener_rule" "api" {
  listener_arn = aws_lb_listener.https.arn
  priority     = 10
  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.a.arn
  }
  condition {
    path_pattern {
      values = ["/api/*"]
    }
  }
}
resource "aws_route53_record" "api" {
  zone_id = var.route53_zone_id
  name    = var.dns_name
  type    = "A"
  alias {
    name                   = aws_lb.api.dns_name
    zone_id                = aws_lb.api.zone_id
    evaluate_target_health = true

  }
}
