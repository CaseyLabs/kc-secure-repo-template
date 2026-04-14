# These variables expose the small set of GitHub repository controls this example manages.
variable "github_owner" {
  description = "GitHub user or organization that will own the repository."
  type        = string
}

variable "repository_name" {
  description = "Repository name."
  type        = string
}

variable "repository_description" {
  description = "Repository description shown in GitHub."
  type        = string
  default     = "Repository managed by Terraform and hardened with GitHub rulesets."
}

variable "repository_visibility" {
  description = "Repository visibility."
  type        = string
  default     = "public"

  validation {
    condition     = contains(["public", "private", "internal"], var.repository_visibility)
    error_message = "repository_visibility must be public, private, or internal."
  }
}

variable "default_branch" {
  description = "Default branch name to manage. Set to null to leave the repository's current default branch unchanged."
  type        = string
  default     = null
  nullable    = true
}

variable "repository_topics" {
  description = "Repository topics to apply."
  type        = list(string)
  default     = []
}

variable "has_issues" {
  description = "Enable GitHub Issues."
  type        = bool
  default     = true
}

variable "has_projects" {
  description = "Enable GitHub Projects."
  type        = bool
  default     = false
}

variable "has_wiki" {
  description = "Enable GitHub Wiki."
  type        = bool
  default     = false
}

variable "has_discussions" {
  description = "Enable GitHub Discussions."
  type        = bool
  default     = false
}

variable "allow_auto_merge" {
  description = "Allow auto-merge."
  type        = bool
  default     = false
}

variable "allow_update_branch" {
  description = "Always suggest updating pull request branches."
  type        = bool
  default     = true
}

variable "allow_merge_commit" {
  description = "Allow merge commits."
  type        = bool
  default     = false
}

variable "allow_squash_merge" {
  description = "Allow squash merges."
  type        = bool
  default     = true
}

variable "allow_rebase_merge" {
  description = "Allow rebase merges."
  type        = bool
  default     = true
}

variable "delete_branch_on_merge" {
  description = "Delete branches automatically after merge."
  type        = bool
  default     = true
}

variable "enable_vulnerability_alerts" {
  description = "Enable Dependabot vulnerability alerts."
  type        = bool
  default     = true
}

variable "enable_dependabot_security_updates" {
  description = "Enable Dependabot security updates."
  type        = bool
  default     = true
}

variable "enable_secret_scanning" {
  description = "Enable repository secret scanning."
  type        = bool
  default     = true
}

variable "enable_secret_scanning_push_protection" {
  description = "Enable secret scanning push protection."
  type        = bool
  default     = true
}

variable "required_approving_review_count" {
  description = "Required pull request approvals."
  type        = number
  default     = 0
}

variable "dismiss_stale_reviews_on_push" {
  description = "Dismiss stale approvals when new commits are pushed."
  type        = bool
  default     = false
}

variable "require_code_owner_review" {
  description = "Require code owner review."
  type        = bool
  default     = false
}

variable "require_last_push_approval" {
  description = "Require the last pusher to be approved by someone else."
  type        = bool
  default     = false
}

variable "required_review_thread_resolution" {
  description = "Require review threads to be resolved before merge."
  type        = bool
  default     = false
}

variable "require_linear_history" {
  description = "Require a linear history on the default branch."
  type        = bool
  default     = true
}

variable "require_signed_commits" {
  description = "Require signed commits on the default branch."
  type        = bool
  default     = false
}

variable "required_status_checks" {
  description = "Status checks to require before merge. Keep empty until the checks exist."
  type        = list(string)
  default = [
    "test-src",
    "test-smoke",
    "scan",
  ]
}

variable "strict_status_checks" {
  description = "Require branches to be up to date before merging when status checks are configured."
  type        = bool
  default     = true
}

variable "archive_on_destroy" {
  description = "Archive the repository instead of deleting it on destroy."
  type        = bool
  default     = true
}

variable "ruleset_enforcement" {
  description = "Ruleset enforcement mode."
  type        = string
  default     = "active"

  validation {
    condition     = contains(["disabled", "active", "evaluate"], var.ruleset_enforcement)
    error_message = "ruleset_enforcement must be disabled, active, or evaluate."
  }
}
