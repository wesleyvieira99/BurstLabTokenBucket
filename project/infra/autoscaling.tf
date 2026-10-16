resource "aws_appautoscaling_target" "worker" {
  count              = var.deploy_apps ? 1 : 0
  max_capacity       = 4
  min_capacity       = 1
  resource_id        = "service/${aws_ecs_cluster.lab.name}/${aws_ecs_service.app["worker"].name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}
resource "aws_appautoscaling_policy" "worker_up" {
  count              = var.deploy_apps ? 1 : 0
  name               = "${var.name}-worker-up"
  policy_type        = "StepScaling"
  resource_id        = aws_appautoscaling_target.worker[0].resource_id
  scalable_dimension = aws_appautoscaling_target.worker[0].scalable_dimension
  service_namespace  = "ecs"
  step_scaling_policy_configuration {
    adjustment_type         = "ChangeInCapacity"
    cooldown                = 60
    metric_aggregation_type = "Maximum"
    step_adjustment {
      metric_interval_lower_bound = 0
      scaling_adjustment          = 1
    }

  }
}
resource "aws_appautoscaling_policy" "worker_down" {
  count              = var.deploy_apps ? 1 : 0
  name               = "${var.name}-worker-down"
  policy_type        = "StepScaling"
  resource_id        = aws_appautoscaling_target.worker[0].resource_id
  scalable_dimension = aws_appautoscaling_target.worker[0].scalable_dimension
  service_namespace  = "ecs"
  step_scaling_policy_configuration {
    adjustment_type         = "ChangeInCapacity"
    cooldown                = 300
    metric_aggregation_type = "Maximum"
    step_adjustment {
      metric_interval_upper_bound = 0
      scaling_adjustment          = -1
    }

  }
}
resource "aws_cloudwatch_metric_alarm" "backlog" {
  count       = var.deploy_apps ? 1 : 0
  alarm_name  = "${var.name}-backlog"
  namespace   = "AWS/SQS"
  metric_name = "ApproximateNumberOfMessagesVisible"
  dimensions = { QueueName = aws_sqs_queue.jobs.name
  }
  statistic           = "Average"
  period              = 60
  evaluation_periods  = 2
  threshold           = 64
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_appautoscaling_policy.worker_up[0].arn]
}
resource "aws_cloudwatch_metric_alarm" "age" {
  count       = var.deploy_apps ? 1 : 0
  alarm_name  = "${var.name}-oldest-job"
  namespace   = "AWS/SQS"
  metric_name = "ApproximateAgeOfOldestMessage"
  dimensions = { QueueName = aws_sqs_queue.jobs.name
  }
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 2
  threshold           = 60
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = concat([aws_appautoscaling_policy.worker_up[0].arn], var.alarm_topic_arn == "" ? [] : [var.alarm_topic_arn])
}
resource "aws_cloudwatch_metric_alarm" "empty" {
  count               = var.deploy_apps ? 1 : 0
  alarm_name          = "${var.name}-queue-empty"
  comparison_operator = "LessThanOrEqualToThreshold"
  evaluation_periods  = 5
  threshold           = 0
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_appautoscaling_policy.worker_down[0].arn]
  metric_query {
    id          = "total"
    expression  = "visible + inflight"
    return_data = true
  }
  metric_query {
    id = "visible"
    metric {
      namespace   = "AWS/SQS"
      metric_name = "ApproximateNumberOfMessagesVisible"
      dimensions = { QueueName = aws_sqs_queue.jobs.name
      }
      period = 60
      stat   = "Maximum"

    }

  }
  metric_query {
    id = "inflight"
    metric {
      namespace   = "AWS/SQS"
      metric_name = "ApproximateNumberOfMessagesNotVisible"
      dimensions = { QueueName = aws_sqs_queue.jobs.name
      }
      period = 60
      stat   = "Maximum"

    }

  }
}
resource "aws_cloudwatch_metric_alarm" "dlq" {
  alarm_name  = "${var.name}-dlq"
  namespace   = "AWS/SQS"
  metric_name = "ApproximateNumberOfMessagesVisible"
  dimensions = { QueueName = aws_sqs_queue.dlq.name
  }
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 1
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = var.alarm_topic_arn == "" ? [] : [var.alarm_topic_arn]
}
resource "aws_cloudwatch_dashboard" "lab" {
  dashboard_name = var.name
  dashboard_body = jsonencode({ widgets = [
    { type = "metric", x = 0, y = 0, width = 12, height = 6, properties = {
      title   = "Fila: visíveis / em andamento", region = var.aws_region, period = 60, stat = "Maximum",
      metrics = [["AWS/SQS", "ApproximateNumberOfMessagesVisible", "QueueName", aws_sqs_queue.jobs.name], ["AWS/SQS", "ApproximateNumberOfMessagesNotVisible", "QueueName", aws_sqs_queue.jobs.name]]
    } },
    { type = "metric", x = 12, y = 0, width = 12, height = 6, properties = {
      title   = "Idade da fila / DLQ", region = var.aws_region, period = 60, stat = "Maximum",
      metrics = [["AWS/SQS", "ApproximateAgeOfOldestMessage", "QueueName", aws_sqs_queue.jobs.name], ["AWS/SQS", "ApproximateNumberOfMessagesVisible", "QueueName", aws_sqs_queue.dlq.name, { yAxis = "right" }]]
    } },
    { type = "metric", x = 0, y = 6, width = 24, height = 6, properties = {
      title   = "Saúde ECS (não é taxa de negócio)", region = var.aws_region, period = 60, stat = "Average",
      metrics = [["AWS/ECS", "CPUUtilization", "ClusterName", aws_ecs_cluster.lab.name, "ServiceName", "service-a"], ["AWS/ECS", "CPUUtilization", "ClusterName", aws_ecs_cluster.lab.name, "ServiceName", "worker"], ["AWS/ECS", "MemoryUtilization", "ClusterName", aws_ecs_cluster.lab.name, "ServiceName", "service-b"]]
      }
    }
  ] })
}
