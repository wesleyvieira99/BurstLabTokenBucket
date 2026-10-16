# Tarefa operacional inativa. Só é executada pelo operador para um UUID revisado.
resource "aws_ecs_task_definition" "maintenance" {
  family                   = "${var.name}-maintenance"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.execution["service-a"].arn
  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }
  container_definitions = jsonencode([{
    name       = "maintenance"
    image      = "public.ecr.aws/docker/library/postgres:16-alpine"
    essential  = true
    entryPoint = ["/bin/sh", "-c"]
    command    = ["set -eu; wget -q https://truststore.pki.rds.amazonaws.com/global/global-bundle.pem -O /tmp/rds.pem; exec psql -v ON_ERROR_STOP=1 -c \"$REPLAY_SQL\""]
    environment = [
      { name = "PGHOST", value = aws_db_instance.db.address },
      { name = "PGDATABASE", value = "burstlab" },
      { name = "PGUSER", value = "burstlab" },
      { name = "PGSSLMODE", value = "verify-full" },
      { name = "PGSSLROOTCERT", value = "/tmp/rds.pem" },
      { name = "REPLAY_SQL", value = "SELECT 1;" }
    ]
    secrets = [{ name = "PGPASSWORD", valueFrom = "${aws_db_instance.db.master_user_secret[0].secret_arn}:password::" }]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        awslogs-group         = aws_cloudwatch_log_group.app["service-a"].name
        awslogs-region        = var.aws_region
        awslogs-stream-prefix = "maintenance"
      }
    }
  }])
}
output "maintenance_task_definition" { value = aws_ecs_task_definition.maintenance.arn }
output "maintenance_network" {
  value = {
    awsvpcConfiguration = {
      subnets        = aws_subnet.private[*].id
      securityGroups = [aws_security_group.app["service-a"].id]
      assignPublicIp = "DISABLED"
    }
  }
}
