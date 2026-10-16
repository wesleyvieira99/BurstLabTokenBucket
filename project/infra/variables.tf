variable "name" {
  type    = string
  default = "burstlab"
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,17}$", var.name))
    error_message = "Use 3–18 caracteres, letras minúsculas, números e hífens."

  }
}
variable "aws_region" {
  type    = string
  default = "us-east-1"
}
variable "certificate_arn" {
  type        = string
  description = "Certificado ACM ISSUED, na mesma região, cobrindo dns_name."
}
variable "dns_name" {
  type        = string
  description = "Nome DNS que será criado na zona Route53, ex. burstlab.seudominio.com."
}
variable "route53_zone_id" {
  type        = string
  description = "ID de zona pública Route53 existente controlada por você."
}
variable "allowed_ingress_cidr" {
  type        = string
  description = "IPv4 CIDR autorizado a acessar a API (prefira seu IP /32). Não é autenticação de usuário."
  validation {
    condition     = can(cidrnetmask(var.allowed_ingress_cidr)) && var.allowed_ingress_cidr != "0.0.0.0/0"
    error_message = "Informe um CIDR IPv4 restrito; a demonstração não permite acesso irrestrito."

  }
}
variable "deploy_apps" {
  type    = bool
  default = false
}
variable "image_tag" {
  type    = string
  default = "lab-v1"
}
variable "rds_multi_az" {
  type    = bool
  default = false
}
variable "deletion_protection" {
  type    = bool
  default = true
}
variable "final_snapshot_identifier" {
  type    = string
  default = "burstlab-final"
}
variable "alarm_topic_arn" {
  type        = string
  default     = ""
  description = "SNS existente com assinaturas confirmadas; vazio cria alarmes sem notificações externas."
}
variable "otel_collector_image" {
  type    = string
  default = "public.ecr.aws/aws-observability/aws-otel-collector:v0.43.3"
}
