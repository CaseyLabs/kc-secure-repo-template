# The caller supplies the GitHub owner so the same example works for a user or org.
provider "github" {
  owner = var.github_owner
}
