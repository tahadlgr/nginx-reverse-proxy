resource "aws_acm_certificate" "nginx_cert" {
  domain_name               = "nginx.exercise.${var.domain_name}"
  validation_method         = "DNS"
  subject_alternative_names = ["*.nginx.exercise.${var.domain_name}"]

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_lb_listener_certificate" "listener_cert" {
  listener_arn    = aws_lb_listener.nginx_lb_listener_https.arn
  certificate_arn = aws_acm_certificate_validation.nginx_cert_validation.certificate_arn
}

resource "aws_acm_certificate_validation" "nginx_cert_validation" {
  certificate_arn         = aws_acm_certificate.nginx_cert.arn
  validation_record_fqdns = [aws_route53_record.cert_nginx_validation.fqdn]
}

resource "aws_route53_record" "cert_nginx_validation" {
  name    = tolist(aws_acm_certificate.nginx_cert.domain_validation_options)[0].resource_record_name
  type    = tolist(aws_acm_certificate.nginx_cert.domain_validation_options)[0].resource_record_type
  zone_id = data.aws_route53_zone.selected.zone_id
  records = [tolist(aws_acm_certificate.nginx_cert.domain_validation_options)[0].resource_record_value]
  ttl     = "300"
}