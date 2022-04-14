provider "kubernetes" {
  config_path = var.kubeconfig_file
}

provider "helm" {
  kubernetes {
    config_path = var.kubeconfig_file
  }
}

locals {
  ingress_annotations = lookup({
    alb = {
      "alb.ingress.kubernetes.io/scheme"      = "internet-facing"
      "alb.ingress.kubernetes.io/tags"        = join(",", [for k, v in var.tags : "${k}=${v}"])
      "alb.ingress.kubernetes.io/target-type" = "ip"
    },
  }, var.ingress_class, {})
}


################################################################################
# CloudBees CD/RO
################################################################################

locals {
  install_cdro    = alltrue([var.install_cdro, local.mysql_endpoint != "", var.cd_admin_password != "", var.cd_host_name != "", var.rwx_storage_class != ""])
  cd_license_data = fileexists(local.cd_license_file) ? file(local.cd_license_file) : ""
  cd_license_file = "${path.module}/${var.cd_license_file}"
  mysql_endpoint  = local.install_mysql ? concat(module.mysql.*.dns_name, [""])[0] : var.database_endpoint
}

module "cloudbees_cd" {
  count  = local.install_cdro ? 1 : 0
  source = "../../modules/cloudbees-cd"

  admin_password      = var.cd_admin_password
  chart_version       = var.cd_chart_version
  ci_oc_url           = "http://${coalesce(module.cloudbees_ci.*.cjoc_url)}"
  database_endpoint   = local.mysql_endpoint
  database_name       = var.database_name
  database_password   = var.database_password
  database_user       = var.database_user
  host_name           = var.cd_host_name
  ingress_annotations = local.ingress_annotations
  ingress_class       = var.ingress_class
  license_data        = local.cd_license_data
  namespace           = var.cd_namespace
  platform            = var.platform
  rwx_storage_class   = var.rwx_storage_class
}


################################################################################
# CloudBees CI
################################################################################

locals {
  install_ci        = alltrue([var.install_ci, var.ci_host_name != ""])
  oc_bundle_data    = { for file in fileset(local.oc_bundle_dir, "*.{yml,yaml}") : file => file("${local.oc_bundle_dir}/${file}") }
  oc_bundle_dir     = "${path.module}/${var.bundle_dir}"
  oc_groovy_data    = { for file in fileset(local.oc_groovy_dir, "*.groovy") : file => file("${local.oc_groovy_dir}/${file}") }
  oc_groovy_dir     = "${path.module}/${var.groovy_dir}"
  oc_secret_data    = fileexists(var.secrets_file) ? yamldecode(file(var.secrets_file)) : {}
  prometheus_labels = { release = "prometheus" }

  prometheus_relabelings = lookup({
    eks = [{
      action       = "replace"
      replacement  = "/$${1}/prometheus/"
      sourceLabels = ["__meta_kubernetes_endpoints_name"]
      targetLabel  = "__metrics_path__"
    }]
  }, var.platform, [])
}

module "cloudbees_ci" {
  count  = local.install_ci ? 1 : 0
  source = "../../modules/cloudbees-ci"

  agent_image                = var.agent_image
  bundle_data                = local.oc_bundle_data
  chart_version              = var.ci_chart_version
  controller_image           = var.controller_image
  create_servicemonitors     = var.create_servicemonitors
  extra_groovy_configuration = local.oc_groovy_data
  host_name                  = var.ci_host_name
  ingress_annotations        = local.ingress_annotations
  ingress_class              = var.ingress_class
  oc_cpu                     = 2
  oc_image                   = var.oc_image
  oc_memory                  = 4
  namespace                  = var.ci_namespace
  oc_configmap_name          = var.oc_configmap_name
  platform                   = var.platform
  prometheus_labels          = local.prometheus_labels
  prometheus_relabelings     = local.prometheus_relabelings
  secret_data                = local.oc_secret_data
}


################################################################################
# MySQL (for CD/RO)
################################################################################

locals {
  install_mysql = alltrue([var.install_mysql, var.database_password != "", var.mysql_root_password != ""])
}

module "mysql" {
  count  = local.install_mysql ? 1 : 0
  source = "../../modules/mysql"

  database_name = var.database_name
  password      = var.database_password
  root_password = var.mysql_root_password
  user_name     = var.database_user
}
