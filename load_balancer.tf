resource "aws_lb" "default" {
  name               = "nginx-lb"
  load_balancer_type = "application"
  subnets            = aws_subnet.subnet.*.id
  security_groups    = [aws_security_group.sg.id]
}

resource "aws_lb_target_group" "nginx_lb_target_group" {
  name        = "nginx-target-group"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "ip"
}

resource "aws_lb_listener" "nginx_lb_listener_http" {
  load_balancer_arn = aws_lb.default.id
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "redirect"
    target_group_arn = aws_lb_target_group.nginx_lb_target_group.id
    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }

}

resource "aws_lb_listener" "nginx_lb_listener_https" {
  load_balancer_arn = aws_lb.default.id
  port              = "443"
  protocol          = "HTTPS"
  certificate_arn   = aws_acm_certificate.nginx_cert.arn

  default_action {
    target_group_arn = aws_lb_target_group.nginx_lb_target_group.id
    type             = "forward"
  }

}

data "aws_route53_zone" "selected" {
  name = "${var.domain_name}."
}

resource "aws_route53_record" "nginx" {
  zone_id         = data.aws_route53_zone.selected.zone_id
  allow_overwrite = true
  name            = "nginx.exercise.${var.domain_name}"
  type            = "A"

  alias {
    name                   = aws_lb.default.dns_name
    zone_id                = aws_lb.default.zone_id
    evaluate_target_health = false
  }
}
