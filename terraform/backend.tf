terraform {
  required_version = ">= 1.11.0"

  backend "s3" {
    encrypt      = true
    use_lockfile = true
  }
}
