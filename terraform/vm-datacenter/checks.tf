# Optional local path to license file: validate readability without putting content in state.
check "consul_enterprise_license_path" {
  assert {
    condition     = var.consul_enterprise_license_path == "" ? true : fileexists(var.consul_enterprise_license_path)
    error_message = "consul_enterprise_license_path must be empty or a path to an existing license file on the machine running Terraform."
  }
}
