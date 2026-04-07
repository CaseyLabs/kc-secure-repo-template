# Surface the most useful values after `terraform plan` or `terraform apply`.
output "repository_name" {
  description = "Repository name."
  value       = github_repository.repository.name
}

output "repository_full_name" {
  description = "Repository full name."
  value       = github_repository.repository.full_name
}

output "repository_html_url" {
  description = "Repository HTML URL."
  value       = github_repository.repository.html_url
}

output "default_branch" {
  description = "Configured default branch."
  value       = github_branch_default.default.branch
}
