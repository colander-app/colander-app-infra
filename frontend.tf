variable "stage" {
  type        = string
  default     = "dev"
  description = "Deployment stage"
}

locals {
  root_domain  = "colanderapp.io"
  stage_domain = "${var.stage}.${local.root_domain}"
  s3_origin_id = "app_s3_origin"
}

# DNS Zone and TLS Certificate
data "aws_route53_zone" "this" {
  name         = local.root_domain
  private_zone = false
}
resource "aws_acm_certificate" "this" {
  domain_name       = local.stage_domain
  subject_alternative_names = [ "*.${local.stage_domain}" ]
  validation_method = "DNS"
}
resource "aws_route53_record" "tls_validation" {
  for_each = {
    for dvo in aws_acm_certificate.this.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = data.aws_route53_zone.this.zone_id
}
resource "aws_acm_certificate_validation" "this" {
  certificate_arn         = aws_acm_certificate.this.arn
  validation_record_fqdns = [for record in aws_route53_record.tls_validation : record.fqdn]
}

# Static CloudFront Distribution Static File Host Resources
resource "aws_s3_bucket" "this" {
  bucket = local.stage_domain
}
resource "aws_s3_bucket_acl" "this" {
  bucket = aws_s3_bucket.this.id
  acl    = "private"
}
resource "aws_s3_bucket_policy" "this" {
  bucket = aws_s3_bucket.this.id
  policy = data.aws_iam_policy_document.this.json
}
data "aws_iam_policy_document" "this" {
  statement {
    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }
    actions = [
      "s3:GetObject",
    ]
    resources = [
      "${aws_s3_bucket.this.arn}/*",
    ]
    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [aws_cloudfront_distribution.this.arn]
    }
  }
}
resource "aws_cloudfront_origin_access_control" "this" {
  name                              = local.stage_domain
  description                       = "${local.stage_domain} Origin Access Control"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}
resource "aws_cloudfront_distribution" "this" {
  enabled         = true
  is_ipv6_enabled = true

  aliases = [local.stage_domain]

  origin {
    domain_name              = aws_s3_bucket.this.bucket_domain_name
    origin_access_control_id = aws_cloudfront_origin_access_control.this.id
    origin_id                = local.s3_origin_id
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  custom_error_response {
    error_code         = "403"
    response_code      = "200"
    response_page_path = "/index.html"
  }

  default_cache_behavior {
    target_origin_id = local.s3_origin_id
    allowed_methods  = ["GET", "HEAD", "OPTIONS"]
    cached_methods   = ["GET", "HEAD"]

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
  }

  viewer_certificate {
    acm_certificate_arn = aws_acm_certificate_validation.this.certificate_arn
    ssl_support_method  = "sni-only"
  }
}

# Point DNS to CF Distribution
resource "aws_route53_record" "ipv4" {
  zone_id         = data.aws_route53_zone.this.zone_id
  name            = local.stage_domain
  type            = "A"
  allow_overwrite = true

  alias {
    name                   = aws_cloudfront_distribution.this.domain_name
    zone_id                = aws_cloudfront_distribution.this.hosted_zone_id
    evaluate_target_health = false
  }
}
resource "aws_route53_record" "ipv6" {
  zone_id         = data.aws_route53_zone.this.zone_id
  name            = local.stage_domain
  type            = "AAAA"
  allow_overwrite = true

  alias {
    name                   = aws_cloudfront_distribution.this.domain_name
    zone_id                = aws_cloudfront_distribution.this.hosted_zone_id
    evaluate_target_health = false
  }
}
