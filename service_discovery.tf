resource "aws_service_discovery_private_dns_namespace" "exercise" {
  name = "exercise.local"
  vpc  = aws_vpc.main.id
}

resource "aws_service_discovery_service" "nginx" {
  name = "nginx"

  dns_config {
    namespace_id = aws_service_discovery_private_dns_namespace.exercise.id

    dns_records {
      ttl  = 10
      type = "A"
    }
  }

  health_check_custom_config {
    failure_threshold = 1
  }
}