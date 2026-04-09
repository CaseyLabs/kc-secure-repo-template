# Compute the GitHub API values from booleans once so the ruleset block stays readable.
locals {
  allowed_merge_methods = compact([
    var.allow_merge_commit ? "merge" : "",
    var.allow_squash_merge ? "squash" : "",
    var.allow_rebase_merge ? "rebase" : "",
  ])
}

resource "github_repository" "repository" {
  name                   = var.repository_name
  description            = var.repository_description
  visibility             = var.repository_visibility
  has_issues             = var.has_issues
  has_projects           = var.has_projects
  has_wiki               = var.has_wiki
  has_discussions        = var.has_discussions
  allow_auto_merge       = var.allow_auto_merge
  allow_update_branch    = var.allow_update_branch
  allow_merge_commit     = var.allow_merge_commit
  allow_squash_merge     = var.allow_squash_merge
  allow_rebase_merge     = var.allow_rebase_merge
  delete_branch_on_merge = var.delete_branch_on_merge
  archive_on_destroy     = var.archive_on_destroy
  vulnerability_alerts   = var.enable_vulnerability_alerts
  auto_init              = true
  topics                 = var.repository_topics

  dynamic "security_and_analysis" {
    # GitHub only exposes these toggles for public repositories.
    for_each = var.repository_visibility == "public" ? [1] : []
    content {
      secret_scanning {
        status = var.enable_secret_scanning ? "enabled" : "disabled"
      }

      secret_scanning_push_protection {
        status = var.enable_secret_scanning_push_protection ? "enabled" : "disabled"
      }
    }
  }
}

resource "github_branch_default" "default" {
  count      = var.default_branch == null ? 0 : 1
  repository = github_repository.repository.name
  branch     = var.default_branch
  rename     = false
}

resource "github_repository_dependabot_security_updates" "repository" {
  repository = github_repository.repository.name
  enabled    = var.enable_dependabot_security_updates
}

resource "github_repository_ruleset" "default_branch" {
  name        = "default-branch-protection"
  repository  = github_repository.repository.name
  target      = "branch"
  enforcement = var.ruleset_enforcement

  conditions {
    ref_name {
      include = ["~DEFAULT_BRANCH"]
      exclude = []
    }
  }

  rules {
    deletion                = true
    non_fast_forward        = true
    required_linear_history = var.require_linear_history
    required_signatures     = var.require_signed_commits

    pull_request {
      allowed_merge_methods             = local.allowed_merge_methods
      dismiss_stale_reviews_on_push     = var.dismiss_stale_reviews_on_push
      require_code_owner_review         = var.require_code_owner_review
      require_last_push_approval        = var.require_last_push_approval
      required_approving_review_count   = var.required_approving_review_count
      required_review_thread_resolution = var.required_review_thread_resolution
    }

    dynamic "required_status_checks" {
      # Leave required checks empty until the repository actually has those jobs.
      for_each = length(var.required_status_checks) > 0 ? [var.required_status_checks] : []
      content {
        strict_required_status_checks_policy = var.strict_status_checks

        dynamic "required_check" {
          for_each = required_status_checks.value
          content {
            context = required_check.value
          }
        }
      }
    }
  }

  depends_on = [github_branch_default.default]
}
