
############################################
# LambdaA Function
############################################

resource "aws_lambda_function" "cookie_generator" {
  function_name = "cookie-generator"
  role          = aws_iam_role.lambda_exec.arn

  runtime = "python3.12"
  handler = "lambda.lambda_handler" 

  # Code from S3 (must be a ZIP)
  s3_bucket         = var.lambda_bucket_name
  s3_key            = var.lambda_zip_path
 # s3_object_version = var.lambda_artifact_version

  layers = [
    aws_lambda_layer_version.cryptography.arn
  ]

  environment {
    variables = {
       # Required
      CLOUDFRONT_DOMAIN                 = var.cloudfront_domain                 # e.g. "photos.example.com"
      CLOUDFRONT_KEY_PAIR_ID            = var.cloudfront_key_pair_id            # e.g. "K1234567890ABCDE"
      CLOUDFRONT_PRIVATE_KEY_SECRET_ARN = var.cloudfront_private_key_secret_arn # Secrets Manager ARN

      # Recommended defaults (optional)
      ALLOWED_FOLDER_PREFIX   = var.allowed_folder_prefix    # e.g. "/clients/"
      DEFAULT_TTL_SECONDS     = tostring(var.default_ttl_seconds) # e.g. 604800
      MAX_TTL_SECONDS         = tostring(var.max_ttl_seconds)     # e.g. 1209600
      REDIRECT_TO_INDEX       = var.redirect_to_index        # "true" or "false"

      COOKIE_SECURE           = var.cookie_secure            # "true"
      COOKIE_HTTPONLY         = var.cookie_httponly          # "true"
      COOKIE_SAMESITE         = var.cookie_samesite          # "Lax" / "Strict" / "None"
      COOKIE_SET_MAX_AGE      = var.cookie_set_max_age       # "false" recommended for session cookies

      COOKIE_DOMAIN           = var.cookie_domain            # usually "photos.example.com"
      COOKIE_PATH             = var.cookie_path              # "/"

       OPEN_PATH              = var.open_path
       
    }
  }

  timeout     = 10
  memory_size = 128
}

############################################
# Crypto Layer
############################################
resource "aws_lambda_layer_version" "cryptography" {
  layer_name          = "cryptography-py312"
  s3_bucket           = var.lambda_bucket_name
  s3_key              = "cryptography-layer.zip"
  compatible_runtimes = ["python3.12"]
}
