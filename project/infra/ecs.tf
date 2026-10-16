resource "aws_ecs_cluster" "lab" {
  name = var.name
  setting {
    name  = "containerInsights"
    value = "enabled"
  }
}
resource "aws_cloudwatch_log_group" "app" {
  for_each          = local.services
  name              = "/burstlab/${var.name}/${each.key}"
  retention_in_days = 14
}
resource "aws_cloudwatch_log_group" "metrics" {
  name              = "/burstlab/${var.name}/metrics"
  retention_in_days = 14
}
resource "aws_ecs_task_definition" "app" {
  for_each                 = local.apps
  family                   = "${var.name}-${each.key}"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "512"
  memory                   = "1024"
  execution_role_arn       = aws_iam_role.execution[each.key].arn
  task_role_arn            = aws_iam_role.task[each.key].arn
  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }
  container_definitions = jsonencode([
    {
      name         = each.key, image = "${aws_ecr_repository.app[each.key].repository_url}:${var.image_tag}", essential = true,
      cpu          = 384, memoryReservation = 640, stopTimeout = 120,
      portMappings = [{ containerPort = each.value, protocol = "tcp" }],
      environment = [for k, v in merge({
        PORT                        = tostring(each.value), ROLE = each.key == "worker" ? "worker" : "a",
        AWS_REGION                  = var.aws_region,
        JDBC_URL                    = "jdbc:postgresql://${aws_db_instance.db.address}:5432/burstlab?sslmode=verify-full&sslrootcert=/app/rds-global-bundle.pem",
        JDBC_USERNAME               = "burstlab", SERVICE_B_URL = "http://service-b.${var.name}.local:8081",
        SQS_QUEUE_URL               = aws_sqs_queue.jobs.url, SQS_DLQ_URL = aws_sqs_queue.dlq.url,
        LIMITER_CAPACITY            = "8", LIMITER_RATE = "32", LIMITER_CONCURRENCY = "8", LIMITER_LEASE_MS = "5000",
        ENABLE_UNPROTECTED          = "false", ENABLE_DEMO_ADMIN = "false",
        B_LATENCY_MS                = "200", B_CAPACITY = "8", B_FAIL_EVERY = "0", WORKER_CONCURRENCY = "4",
        JAVA_TOOL_OPTIONS           = "-XX:MaxRAMPercentage=65 -javaagent:/app/opentelemetry-javaagent.jar",
        OTEL_SERVICE_NAME           = each.key, OTEL_RESOURCE_ATTRIBUTES = "deployment.environment.name=aws-lab,service.namespace=burstlab",
        OTEL_EXPORTER_OTLP_ENDPOINT = "http://127.0.0.1:4317", OTEL_EXPORTER_OTLP_PROTOCOL = "grpc",
        OTEL_TRACES_EXPORTER        = "otlp", OTEL_METRICS_EXPORTER = "none", OTEL_LOGS_EXPORTER = "none",
        OTEL_TRACES_SAMPLER         = "parentbased_traceidratio", OTEL_TRACES_SAMPLER_ARG = "0.1"
      }, {}) : { name = k, value = v }],
      secrets          = concat([{ name = "JDBC_PASSWORD", valueFrom = "${aws_db_instance.db.master_user_secret[0].secret_arn}:password::" }], each.key == "service-b" ? [] : [{ name = "REDIS_URI", valueFrom = aws_secretsmanager_secret.redis.arn }]),
      logConfiguration = { logDriver = "awslogs", options = { awslogs-group = aws_cloudwatch_log_group.app[each.key].name, awslogs-region = var.aws_region, awslogs-stream-prefix = "app" } },
      dependsOn        = [{ containerName = "otel", condition = "START" }],
      healthCheck = { command = ["CMD-SHELL", "curl -fsS http://localhost:${each.value}/actuator/health > /dev/null || exit 1"], interval = 30, timeout = 5, retries = 3, startPeriod = 90
      }
    },
    {
      name        = "otel", image = var.otel_collector_image, essential = false,
      cpu         = 128, memoryReservation = 128,
      environment = [{ name = "AOT_CONFIG_CONTENT", value = templatefile("${path.module}/otel-config.yaml.tftpl", { region = var.aws_region, port = each.value, service = each.key, metrics_log_group = aws_cloudwatch_log_group.metrics.name }) }],
      logConfiguration = { logDriver = "awslogs", options = { awslogs-group = aws_cloudwatch_log_group.app[each.key].name, awslogs-region = var.aws_region, awslogs-stream-prefix = "otel" }
      }

    }
  ])
}
resource "aws_ecs_service" "app" {
  for_each                           = local.apps
  name                               = each.key
  cluster                            = aws_ecs_cluster.lab.id
  task_definition                    = aws_ecs_task_definition.app[each.key].arn
  desired_count                      = each.key == "service-b" ? 1 : 2
  launch_type                        = "FARGATE"
  platform_version                   = "1.4.0"
  deployment_minimum_healthy_percent = each.key == "service-b" ? 0 : 100
  deployment_maximum_percent         = each.key == "service-b" ? 100 : 200
  health_check_grace_period_seconds  = each.key == "service-a" ? 120 : null
  enable_execute_command             = false
  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }
  network_configuration {
    subnets          = aws_subnet.private[*].id
    security_groups  = [aws_security_group.app[each.key].id]
    assign_public_ip = false

  }
  dynamic "load_balancer" {
    for_each = each.key == "service-a" ? [1] : []
    content {
      target_group_arn = aws_lb_target_group.a.arn
      container_name   = each.key
      container_port   = each.value
    }

  }
  dynamic "service_registries" {
    for_each = each.key == "service-b" ? [1] : []
    content {
      registry_arn = aws_service_discovery_service.b.arn
    }

  }
  lifecycle {
    ignore_changes = [desired_count]
  }
  depends_on = [aws_lb_listener_rule.api, aws_iam_role_policy.execution, aws_iam_role_policy.telemetry, aws_iam_role_policy.queue_a, aws_iam_role_policy.queue_worker, aws_secretsmanager_secret_version.redis]
}
