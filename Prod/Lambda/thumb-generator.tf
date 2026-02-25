############################################
# Thumb Generator
############################################

resource "aws_lambda_function" "thumb_generator" {
  function_name = "thumb-generator"
  role          = aws_iam_role.lambda_thumb.arn

  runtime = "python3.12"
  handler = "lambda-thumb.lambda_handler" 


  s3_bucket         = var.lambda_bucket_name
  s3_key            = var.lambda_thumb_zip_path

  layers = [
    aws_lambda_layer_version.pillow.arn
  ]

  environment {
    variables = {

    SOURCE_PREFIX = "gallery/"
    THUMB_DIRNAME = "thumbs/"
    THUMB_PREFIX  = "thumb-of-"

    # Thumb output size (I recommend 640 for your grid, but you can keep 480)
    THUMB_MAX_SIZE = "640"
    JPEG_QUALITY   = "75"
    CACHE_CONTROL  = "public, max-age=31536000, immutable"

    CREATE_THUMB_FOLDER_MARKER = "true"

    # NEW: decide when to generate thumbs
    THUMB_DECIDER_MODE            = "bytes"     # bytes | pixels
    THUMB_DECIDER_MIN_MIB         = "1"         # create thumb only if original >= 1 MiB
    THUMB_DECIDER_MIN_MAXDIM_PX   = "0"         # unused in bytes mode
       
    }
  }

  timeout     = 10
  memory_size = 512
}


############################################
# Pillow Layer
############################################
resource "aws_lambda_layer_version" "pillow" {
  layer_name          = "pillow-py312"
  s3_bucket           = var.lambda_bucket_name
  s3_key              = "pillow-layer.zip"
  compatible_runtimes = ["python3.12"]
}


############################################
# Premission for S3 to invoke lambda
############################################

resource "aws_lambda_permission" "allow_s3_invoke_thumb" {
  statement_id  = "AllowExecutionFromS3"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.thumb_generator.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = var.gallery_bucket_arn
}