# Residency guard-rail tests. Run with: terraform -chdir=infra/modules/aws-stack test
# Uses mock providers only: no credentials, no AWS API calls, nothing created.

mock_provider "aws" {
  mock_data "aws_region" {
    defaults = { region = "eu-central-1" }
  }
  mock_data "aws_availability_zones" {
    defaults = { names = ["eu-central-1a", "eu-central-1b", "eu-central-1c"] }
  }
  # Random mock strings are not valid JSON/ARNs, which the provider and the
  # community modules validate; give them syntactically valid placeholders.
  mock_data "aws_iam_policy_document" {
    defaults = { json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}" }
  }
  mock_data "aws_caller_identity" {
    defaults = { account_id = "123456789012", arn = "arn:aws:iam::123456789012:role/mock" }
  }
  mock_data "aws_iam_session_context" {
    defaults = { issuer_arn = "arn:aws:iam::123456789012:role/mock" }
  }
  mock_data "aws_partition" {
    defaults = { partition = "aws" }
  }
}

# random is used for real: it is local-only (no network) and mock providers
# do not support ephemeral resources yet.

variables {
  stack_name                    = "test-eu"
  tenant_id                     = "test"
  deployment_mode               = "dedicated"
  cluster_endpoint_public_cidrs = ["203.0.113.0/24"]
}

run "eu_tenant_in_us_region_is_rejected" {
  command = plan

  variables {
    data_residency = "eu"
    region         = "us-east-1"
  }

  expect_failures = [var.region]
}

run "provider_region_must_match_declared_region" {
  command = plan

  # var.region says eu-west-1, but the (mocked) provider is in eu-central-1.
  variables {
    data_residency = "eu"
    region         = "eu-west-1"
  }

  expect_failures = [aws_kms_key.this]
}

run "invalid_deployment_mode_is_rejected" {
  command = plan

  variables {
    deployment_mode = "hybrid"
    data_residency  = "eu"
    region          = "eu-central-1"
  }

  expect_failures = [var.deployment_mode]
}

run "eu_tenant_in_eu_region_plans" {
  command = plan

  variables {
    data_residency = "eu"
    region         = "eu-central-1"
  }

  assert {
    condition     = output.data_residency == "eu" && output.region == "eu-central-1"
    error_message = "Contract outputs must report the stack's residency and region."
  }

  assert {
    condition     = aws_kms_key.this.tags["data_residency"] == "eu" && aws_kms_key.this.tags["tenant_id"] == "test"
    error_message = "Residency/tenant tags must be applied."
  }
}
