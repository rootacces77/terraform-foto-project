
############################################
# Gallery Bucket EVENT
############################################
resource "aws_s3_bucket_notification" "thumb_event_media" {
  bucket = var.gallery_bucket_name

  # Images
  lambda_function { 
   lambda_function_arn = var.lambda_thumb_arn
   events = ["s3:ObjectCreated:Put","s3:ObjectCreated:CompleteMultipartUpload"] 
   filter_prefix = "gallery/" 
   filter_suffix = ".jpg" 
  }

  lambda_function { 
   lambda_function_arn = var.lambda_thumb_arn 
   events = ["s3:ObjectCreated:Put","s3:ObjectCreated:CompleteMultipartUpload"] 
   filter_prefix = "gallery/" 
   filter_suffix = ".jpeg" 
  }
  lambda_function { 
    lambda_function_arn = var.lambda_thumb_arn 
     events = ["s3:ObjectCreated:Put","s3:ObjectCreated:CompleteMultipartUpload"] 
     filter_prefix = "gallery/" 
    filter_suffix = ".png" 
  }
  lambda_function { 
    lambda_function_arn = var.lambda_thumb_arn 
    events = ["s3:ObjectCreated:Put","s3:ObjectCreated:CompleteMultipartUpload"] 
    filter_prefix = "gallery/" 
    filter_suffix = ".webp" 
  }
  lambda_function { 
    lambda_function_arn = var.lambda_thumb_arn 
    events = ["s3:ObjectCreated:Put","s3:ObjectCreated:CompleteMultipartUpload"] 
    filter_prefix = "gallery/" 
    filter_suffix = ".gif"  
  }

  # Videos
  lambda_function { 
    lambda_function_arn = var.lambda_thumb_arn 
    events = ["s3:ObjectCreated:Put","s3:ObjectCreated:CompleteMultipartUpload"] 
    filter_prefix = "gallery/" 
    filter_suffix = ".mp4"  
  }
  lambda_function { 
    lambda_function_arn = var.lambda_thumb_arn 
    events = ["s3:ObjectCreated:Put","s3:ObjectCreated:CompleteMultipartUpload"] 
    filter_prefix = "gallery/" 
    filter_suffix = ".mov"  
  }
  lambda_function { 
    lambda_function_arn = var.lambda_thumb_arn 
    events = ["s3:ObjectCreated:Put","s3:ObjectCreated:CompleteMultipartUpload"] 
    filter_prefix = "gallery/" 
    filter_suffix = ".webm" 
  }
  lambda_function { 
    lambda_function_arn = var.lambda_thumb_arn 
    events = ["s3:ObjectCreated:Put","s3:ObjectCreated:CompleteMultipartUpload"] 
    filter_prefix = "gallery/" 
    filter_suffix = ".m4v"  
    }
}


############################################
# .jpg EVENT
############################################

/*
resource "aws_s3_bucket_notification" "thumb_event_jpg" {
  bucket = module.gallery-bucket.s3_bucket_id

  lambda_function {
    lambda_function_arn = var.lambda_thumb_arn
    events              = ["s3:ObjectCreated:Put", "s3:ObjectCreated:CompleteMultipartUpload"]
    filter_prefix       = "gallery/"
    filter_suffix       = ".jpg"
  }

}


############################################
# .png EVENT
############################################

resource "aws_s3_bucket_notification" "thumb_event_png" {
  bucket = module.gallery-bucket.s3_bucket_id

  lambda_function {
    lambda_function_arn = var.lambda_thumb_arn
    events              = ["s3:ObjectCreated:Put", "s3:ObjectCreated:CompleteMultipartUpload"]
    filter_prefix       = "gallery/"
    filter_suffix       = ".png"
  }

}


############################################
# .jpeg EVENT
############################################

resource "aws_s3_bucket_notification" "thumb_event_jpeg" {
  bucket = module.gallery-bucket.s3_bucket_id

  lambda_function {
    lambda_function_arn = var.lambda_thumb_arn
    events              = ["s3:ObjectCreated:Put", "s3:ObjectCreated:CompleteMultipartUpload"]
    filter_prefix       = "gallery/"
    filter_suffix       = ".jpeg"
  }

}


############################################
# .webp EVENT
############################################

resource "aws_s3_bucket_notification" "thumb_event_webp" {
  bucket = module.gallery-bucket.s3_bucket_id

  lambda_function {
    lambda_function_arn = var.lambda_thumb_arn
    events              = ["s3:ObjectCreated:Put", "s3:ObjectCreated:CompleteMultipartUpload"]
    filter_prefix       = "gallery/"
    filter_suffix       = ".webp"
  }

}
*/