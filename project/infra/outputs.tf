output "region" {
  value = var.aws_region
}
output "cluster_name" {
  value = aws_ecs_cluster.lab.name
}
output "api_url" {
  value = "https://${var.dns_name}"
}
output "ecr_repositories" {
  value = { for k, v in aws_ecr_repository.app : k => v.repository_url }
}
output "queue_url" {
  value = aws_sqs_queue.jobs.url
}
output "dlq_url" {
  value = aws_sqs_queue.dlq.url
}
output "db_identifier" {
  value = aws_db_instance.db.id
}
output "redis_replication_group" {
  value = aws_elasticache_replication_group.redis.id
}
output "redis_engine_version_actual" {
  value = aws_elasticache_replication_group.redis.engine_version_actual
}
output "postgres_engine_version_actual" {
  value = aws_db_instance.db.engine_version_actual
}
output "log_groups" {
  value = { for k, v in aws_cloudwatch_log_group.app : k => v.name }
}
output "dashboard_url" {
  value = "https://${var.aws_region}.console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#dashboards:name=${aws_cloudwatch_dashboard.lab.dashboard_name}"
}
