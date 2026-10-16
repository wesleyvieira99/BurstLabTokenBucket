resource "aws_sqs_queue" "dlq" {
  name                      = "${var.name}-dlq"
  message_retention_seconds = 1209600
  sqs_managed_sse_enabled   = true
}
resource "aws_sqs_queue" "jobs" {
  name                       = "${var.name}-jobs"
  message_retention_seconds  = 345600
  receive_wait_time_seconds  = 20
  visibility_timeout_seconds = 45
  sqs_managed_sse_enabled    = true
  # Recebimentos sem token não são falhas. O worker encaminha falhas terminais
  # pela outbox; não configure redrive_policy com maxReceiveCount nesta fila.
}
resource "aws_sqs_queue_policy" "tls" {
  for_each = { jobs = aws_sqs_queue.jobs, dlq = aws_sqs_queue.dlq
  }
  queue_url = each.value.url
  policy = jsonencode({ Version = "2012-10-17", Statement = [{
    Effect = "Deny", Principal = "*", Action = "sqs:*", Resource = each.value.arn,
    Condition = { Bool = { "aws:SecureTransport" = "false" }
    }
  }] })
}
resource "random_password" "redis" {
  length  = 40
  special = false
}
resource "aws_elasticache_subnet_group" "redis" {
  name       = "${var.name}-redis"
  subnet_ids = aws_subnet.private[*].id
}
resource "aws_elasticache_parameter_group" "redis" {
  name   = "${var.name}-redis7"
  family = "redis7"
  parameter {
    name  = "maxmemory-policy"
    value = "noeviction"
  }
}
resource "aws_elasticache_replication_group" "redis" {
  replication_group_id       = "${var.name}-redis"
  description                = "Estado compartilhado do limitador BurstLab"
  engine                     = "redis"
  engine_version             = "7.1"
  node_type                  = "cache.t4g.small"
  num_cache_clusters         = 2
  automatic_failover_enabled = true
  multi_az_enabled           = true
  port                       = 6379
  parameter_group_name       = aws_elasticache_parameter_group.redis.name
  subnet_group_name          = aws_elasticache_subnet_group.redis.name
  security_group_ids         = [aws_security_group.redis.id]
  at_rest_encryption_enabled = true
  transit_encryption_enabled = true
  transit_encryption_mode    = "required"
  auth_token                 = random_password.redis.result
  auth_token_update_strategy = "SET"
  snapshot_retention_limit   = 1
  auto_minor_version_upgrade = true
  apply_immediately          = false
}
resource "aws_db_subnet_group" "db" {
  name       = "${var.name}-db"
  subnet_ids = aws_subnet.private[*].id
}
resource "aws_db_parameter_group" "db" {
  name_prefix = "${var.name}-pg16-"
  family      = "postgres16"
  parameter {
    name  = "rds.force_ssl"
    value = "1"
  }
}
resource "aws_db_instance" "db" {
  identifier                      = "${var.name}-db"
  engine                          = "postgres"
  engine_version                  = "16"
  instance_class                  = "db.t4g.small"
  allocated_storage               = 20
  max_allocated_storage           = 100
  storage_type                    = "gp3"
  storage_encrypted               = true
  db_name                         = "burstlab"
  username                        = "burstlab"
  manage_master_user_password     = true
  db_subnet_group_name            = aws_db_subnet_group.db.name
  parameter_group_name            = aws_db_parameter_group.db.name
  vpc_security_group_ids          = [aws_security_group.db.id]
  publicly_accessible             = false
  multi_az                        = var.rds_multi_az
  backup_retention_period         = 7
  auto_minor_version_upgrade      = true
  deletion_protection             = var.deletion_protection
  skip_final_snapshot             = false
  final_snapshot_identifier       = var.final_snapshot_identifier
  copy_tags_to_snapshot           = true
  enabled_cloudwatch_logs_exports = ["postgresql"]
}
resource "aws_secretsmanager_secret" "redis" {
  name_prefix             = "${var.name}-redis-uri-"
  recovery_window_in_days = 7
}
resource "aws_secretsmanager_secret_version" "redis" {
  secret_id     = aws_secretsmanager_secret.redis.id
  secret_string = "rediss://default:${random_password.redis.result}@${aws_elasticache_replication_group.redis.primary_endpoint_address}:6379"
}
