# Plans with mocked AWS: no credentials, no calls, no paid resources.
mock_provider "aws" {
  mock_data "aws_iam_policy_document" {
    defaults = { json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}" }
  }
  mock_data "aws_availability_zones" {
    defaults = { names = ["us-east-1a", "us-east-1b"] }
  }
  mock_data "aws_caller_identity" {
    defaults = { account_id = "123456789012" }
  }
  mock_data "aws_partition" {
    defaults = { partition = "aws" }
  }
}
mock_provider "random" {}
variables {
  certificate_arn      = "arn:aws:acm:us-east-1:123456789012:certificate/00000000-0000-0000-0000-000000000000"
  route53_zone_id      = "Z000000000000EXAMPLE"
  dns_name             = "burstlab.example.com"
  allowed_ingress_cidr = "203.0.113.10/32"
}
run "base_without_app_images" {
  command = plan
  assert {
    condition     = length(aws_ecs_service.app) == 0
    error_message = "A fase base não deve iniciar aplicações antes do push."
  }
  assert {
    condition     = aws_elasticache_replication_group.redis.engine == "redis" && aws_elasticache_replication_group.redis.engine_version == "7.1"
    error_message = "O laboratório precisa do engine Redis OSS explicitamente."
  }
  assert {
    condition     = aws_sqs_queue.jobs.receive_wait_time_seconds == 20 && aws_sqs_queue.jobs.visibility_timeout_seconds == 45
    error_message = "Long polling e visibilidade precisam manter o contrato do worker."
  }
}
run "applications_share_bounded_workers" {
  command = plan
  variables { deploy_apps = true }
  assert {
    condition     = length(aws_ecs_service.app) == 3
    error_message = "A, B e worker devem estar definidos."
  }
  assert {
    condition     = aws_appautoscaling_target.worker[0].max_capacity == 4 && aws_appautoscaling_target.worker[0].min_capacity == 1
    error_message = "Escala de workers precisa permanecer limitada."
  }
  assert {
    condition     = alltrue([for app in aws_ecs_service.app : app.network_configuration[0].assign_public_ip == false])
    error_message = "As tarefas não podem receber IP público."
  }
}
