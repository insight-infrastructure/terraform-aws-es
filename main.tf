
# inspired by https://github.com/hashicorp/terraform/issues/20692
# I use 0.12 new "dynamic" block - https://www.terraform.io/docs/configuration/expressions.html
# If we have 1 az - the count of this resource equals 0, hence no config
# block appears in the `aws_elasticsearch_domain`
# If we have more than 1 - we set the trigger to the actual value of
# `availability_zone_count`
# and `dynamic` block kicks in
resource "null_resource" "azs" {
  count = var.availability_zone_count > 1 ? 1 : 0
  triggers = {
    availability_zone_count = var.availability_zone_count
  }
}

resource "aws_elasticsearch_domain" "default" {
  count                 = 1
  domain_name           = var.id
  elasticsearch_version = var.elasticsearch_version

  advanced_options = var.advanced_options

  advanced_security_options {
    enabled                        = var.advanced_security_options_enabled
    internal_user_database_enabled = var.advanced_security_options_internal_user_database_enabled
    master_user_options {
      master_user_arn      = var.advanced_security_options_master_user_arn
      master_user_name     = var.advanced_security_options_master_user_name
      master_user_password = var.advanced_security_options_master_user_password
    }
  }

  ebs_options {
    ebs_enabled = var.ebs_volume_size > 0
    volume_size = var.ebs_volume_size
    volume_type = var.ebs_volume_type
    iops        = var.ebs_iops
  }

  encrypt_at_rest {
    enabled    = var.encrypt_at_rest_kms_key_id != ""
    kms_key_id = var.encrypt_at_rest_kms_key_id
  }

  domain_endpoint_options {
    enforce_https       = var.domain_endpoint_options_enforce_https
    tls_security_policy = var.domain_endpoint_options_tls_security_policy
  }

  cluster_config {
    instance_count           = var.instance_count
    instance_type            = var.instance_type
    dedicated_master_enabled = var.dedicated_master_enabled
    dedicated_master_count   = var.dedicated_master_count
    dedicated_master_type    = var.dedicated_master_type
    zone_awareness_enabled   = var.zone_awareness_enabled
    warm_enabled             = var.warm_enabled
    warm_count               = var.warm_count
    warm_type                = var.warm_type

    dynamic "zone_awareness_config" {
      for_each = null_resource.azs[*].triggers
      content {
        availability_zone_count = zone_awareness_config.value.availability_zone_count
      }
    }
  }

  node_to_node_encryption {
    enabled = var.node_to_node_encryption_enabled
  }

  //  dynamic "vpc_options" {
  //    for_each = true
  //
  //    content {
  //      security_group_ids = [join("", aws_security_group.this.*.id)]
  //      subnet_ids         = var.subnet_ids
  //    }
  //  }

  snapshot_options {
    automated_snapshot_start_hour = var.automated_snapshot_start_hour
  }

  dynamic "cognito_options" {
    for_each = var.cognito_user_pool_id != "" ? [true] : []
    content {
      enabled          = true
      user_pool_id     = var.cognito_user_pool_id
      identity_pool_id = var.cognito_identity_pool_id
      role_arn         = var.cognito_iam_role_arn
    }
  }

  log_publishing_options {
    enabled                  = var.log_publishing_index_cloudwatch_log_group_arn != ""
    log_type                 = "INDEX_SLOW_LOGS"
    cloudwatch_log_group_arn = var.log_publishing_index_cloudwatch_log_group_arn
  }

  log_publishing_options {
    enabled                  = var.log_publishing_search_cloudwatch_log_group_arn != ""
    log_type                 = "SEARCH_SLOW_LOGS"
    cloudwatch_log_group_arn = var.log_publishing_search_cloudwatch_log_group_arn
  }

  log_publishing_options {
    enabled                  = var.log_publishing_index_cloudwatch_log_group_arn != ""
    log_type                 = "ES_APPLICATION_LOGS"
    cloudwatch_log_group_arn = var.log_publishing_application_cloudwatch_log_group_arn
  }

  tags = var.tags

  depends_on = [aws_iam_service_linked_role.default]
}

data "aws_iam_policy_document" "default" {
  count = (length(var.iam_authorizing_role_arns) > 0 || length(var.iam_role_arns) > 0) ? 1 : 0

  statement {
    actions = distinct(compact(var.iam_actions))

    resources = [
      join("", aws_elasticsearch_domain.default.*.arn),
      "${join("", aws_elasticsearch_domain.default.*.arn)}/*"
    ]

    principals {
      type        = "AWS"
      identifiers = distinct(compact(concat(var.iam_role_arns, aws_iam_role.elasticsearch_user.*.arn)))
    }

    # This condition is for non VPC ES to allow anonymous access from whitelisted IP ranges without requests signing
    # https://docs.aws.amazon.com/elasticsearch-service/latest/developerguide/es-ac.html#es-ac-types-ip
    # https://aws.amazon.com/premiumsupport/knowledge-center/anonymous-not-authorized-elasticsearch/
    //    dynamic "condition" {
    //      for_each = ! var.vpc_enabled && length(var.allowed_cidr_blocks) > 0 ? [true] : []
    //
    //      content {
    //        test     = "IpAddress"
    //        values   = var.allowed_cidr_blocks
    //        variable = "aws:SourceIp"
    //      }
    //    }
  }
}

resource "aws_elasticsearch_domain_policy" "default" {
  count           = length(var.iam_authorizing_role_arns) > 0 || length(var.iam_role_arns) > 0 ? 1 : 0
  domain_name     = var.id
  access_policies = join("", data.aws_iam_policy_document.default.*.json)
}



data "aws_route53_zone" "this" {
  count = var.domain_name == "" ? 0 : 1
  name  = "${var.domain_name}."
}

resource "aws_route53_record" "domain_hostname" {
  count = var.domain_name == "" ? 0 : 1

  name    = var.elasticsearch_subdomain_name
  zone_id = join("", data.aws_route53_zone.this.*.zone_id)
  type    = "CNAME"
  ttl     = var.ttl
  records = [join("", aws_elasticsearch_domain.default.*.endpoint)]
}

resource "aws_route53_record" "kibana_hostname" {
  count   = var.domain_name == "" ? 0 : 1
  name    = var.kibana_subdomain_name
  zone_id = join("", data.aws_route53_zone.this.*.zone_id)
  type    = "CNAME"
  ttl     = var.ttl
  records = [join("", aws_elasticsearch_domain.default.*.kibana_endpoint)]
}
