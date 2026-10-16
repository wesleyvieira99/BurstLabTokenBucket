resource "aws_ecr_repository" "app" {
  for_each             = local.services
  name                 = "${var.name}/${each.key}"
  image_tag_mutability = "IMMUTABLE"
  image_scanning_configuration {
    scan_on_push = true
  }
  encryption_configuration {
    encryption_type = "AES256"
  }
  force_delete = false
}
resource "aws_ecr_lifecycle_policy" "app" {
  for_each   = aws_ecr_repository.app
  repository = each.value.name
  policy = jsonencode({ rules = [{ rulePriority = 1, description = "Remover imagens sem tag antigas", selection = {
    tagStatus = "untagged", countType = "sinceImagePushed", countUnit = "days", countNumber = 7
  }, action = { type = "expire" } }] })
}
