terraform {
  required_providers {
    yandex = {
      source = "yandex-cloud/yandex"
    }
  }
  required_version = ">= 0.13"
}

provider "yandex" {
  service_account_key_file = "key.json"
  cloud_id                 = var.cloud_id
  folder_id                = var.folder_id
  zone                     = var.zone
}

resource "yandex_iam_service_account" "sa" {
  name        = "${var.folder_name}-editor"
  description = "Service account to manage Object Storage"
}

resource "yandex_resourcemanager_folder_iam_member" "editor_role" {
  folder_id = var.folder_id
  role      = "editor"
  member    = "serviceAccount:${yandex_iam_service_account.sa.id}"
}

resource "yandex_resourcemanager_folder_iam_member" "queue_role" {
  folder_id = var.folder_id
  role      = "ymq.admin"
  member    = "serviceAccount:${yandex_iam_service_account.sa.id}"
}

resource "yandex_resourcemanager_folder_iam_member" "invoker_iam" {
  folder_id = var.folder_id
  role      = "serverless.functions.invoker"
  member    = "serviceAccount:${yandex_iam_service_account.sa.id}"
}

resource "yandex_iam_service_account_static_access_key" "sa-static-key" {
  service_account_id = yandex_iam_service_account.sa.id
  description        = "Static access key for object storage"
}

resource "yandex_storage_bucket" "photos_bucket" {
  access_key = yandex_iam_service_account_static_access_key.sa-static-key.access_key
  secret_key = yandex_iam_service_account_static_access_key.sa-static-key.secret_key
  bucket     = "${var.folder_name}-photos"
  max_size   = 1073741824
}

resource "yandex_storage_bucket" "faces_bucket" {
  access_key = yandex_iam_service_account_static_access_key.sa-static-key.access_key
  secret_key = yandex_iam_service_account_static_access_key.sa-static-key.secret_key
  bucket     = "${var.folder_name}-faces"
  max_size   = 1073741824
}

resource "yandex_function_trigger" "face_detection_trigger" {
  name        = "${var.folder_name}-photo"
  description = "Trigger on adding images to Photos Bucket"
  object_storage {
    bucket_id    = yandex_storage_bucket.photos_bucket.id
    create       = true
    suffix       = ".jpg"
    batch_cutoff = 3
  }
  function {
    id                 = yandex_function.face_detection.id
    service_account_id = yandex_iam_service_account.sa.id
  }
}

resource "yandex_function" "face_detection" {
  name               = "${var.folder_name}-face-detection"
  description        = "Face detection Function"
  user_hash          = "any_user_defined_string"
  runtime            = "python312"
  entrypoint         = "index.handler"
  memory             = "128"
  execution_timeout  = "10"
  service_account_id = yandex_iam_service_account.sa.id
  tags               = ["my_tag"]
  content {
    zip_filename = "face_detection.zip"
  }

  environment = {
    QUEUE_URL             = yandex_message_queue.queue.id
    FOLDER_ID             = var.folder_id
    AWS_ACCESS_KEY_ID     = yandex_iam_service_account_static_access_key.sa-static-key.access_key
    AWS_SECRET_ACCESS_KEY = yandex_iam_service_account_static_access_key.sa-static-key.secret_key
    AWS_DEFAULT_REGION    = var.zone
  }
}

resource "yandex_message_queue" "queue" {
  name                       = "${var.folder_name}-task"
  visibility_timeout_seconds = 600
  receive_wait_time_seconds  = 20
  message_retention_seconds  = 1209600
  access_key                 = yandex_iam_service_account_static_access_key.sa-static-key.access_key
  secret_key                 = yandex_iam_service_account_static_access_key.sa-static-key.secret_key
}

resource "yandex_function_trigger" "queue_trigger" {
  name        = "${var.folder_name}-task"
  description = "Trigger for Detected faces Queue"
  message_queue {
    queue_id           = yandex_message_queue.queue.arn
    service_account_id = yandex_iam_service_account.sa.id
    batch_size         = "1"
    batch_cutoff       = "10"
  }
  function {
    id                 = yandex_function.face_cut.id
    service_account_id = yandex_iam_service_account.sa.id
  }
}

resource "yandex_function" "face_cut" {
  name               = "${var.folder_name}-face-cut"
  description        = "Face cut Function"
  user_hash          = "any_user_defined_string"
  runtime            = "python312"
  entrypoint         = "index.handler"
  memory             = "128"
  execution_timeout  = "10"
  service_account_id = yandex_iam_service_account.sa.id
  tags               = ["my_tag"]
  content {
    zip_filename = "face_cut.zip"
  }

  environment = {
    FOLDER_ID             = var.folder_id
    SOURCE_BUCKET_ID      = yandex_storage_bucket.photos_bucket.id
    TARGET_BUCKET_ID      = yandex_storage_bucket.faces_bucket.id
    DATABASE_ENDPOINT     = "https://docapi.serverless.yandexcloud.net/${var.zone}/${var.cloud_id}/${yandex_ydb_database_serverless.database.id}"
    AWS_ACCESS_KEY_ID     = yandex_iam_service_account_static_access_key.sa-static-key.access_key
    AWS_SECRET_ACCESS_KEY = yandex_iam_service_account_static_access_key.sa-static-key.secret_key
    AWS_DEFAULT_REGION    = var.zone
  }
}

resource "yandex_ydb_database_serverless" "database" {
  name                = "${var.folder_name}-db-photo-face"
  deletion_protection = "false"

  serverless_database {
    storage_size_limit = 5
  }
}

resource "yandex_function" "bot" {
  name               = "${var.folder_name}-boot"
  description        = "Telegram bot function"
  user_hash          = "any_user_defined_string"
  runtime            = "python312"
  entrypoint         = "index.handler"
  memory             = "128"
  execution_timeout  = "10"
  service_account_id = yandex_iam_service_account.sa.id
  tags               = ["my_tag"]
  content {
    zip_filename = "bot.zip"
  }
  environment = {
    BOT_TOKEN             = var.bot_key
    DATABASE_ENDPOINT     = "https://docapi.serverless.yandexcloud.net/${var.zone}/${var.cloud_id}/${yandex_ydb_database_serverless.database.id}"
    API_GATEWAY_ID        = yandex_api_gateway.gateway.id
    AWS_ACCESS_KEY_ID     = yandex_iam_service_account_static_access_key.sa-static-key.access_key
    AWS_SECRET_ACCESS_KEY = yandex_iam_service_account_static_access_key.sa-static-key.secret_key
    AWS_DEFAULT_REGION    = var.zone
  }
}

resource "yandex_function_iam_binding" "bot-iam" {
  function_id = yandex_function.bot.id
  role        = "serverless.functions.invoker"

  members = [
    "system:allUsers",
  ]
}

output "bot_id" {
  value = yandex_function.bot.id
}

data "http" "webhook" {
  url = "https://api.telegram.org/bot${var.bot_key}/setWebhook?url=https://functions.yandexcloud.net/${yandex_function.bot.id}"
}

resource "yandex_api_gateway" "gateway" {
  name        = "${var.folder_name}-apigw"
  description = "API Gateway for face photos"
  labels = {
    label       = "label"
    empty-label = ""
  }
  spec = <<-EOT
openapi: 3.0.0
info:
  title: ${var.folder_name}-apigw
  version: 1.0.0
paths:
  /:
    get:
      parameters:
      - name: face
        in: query
        description: 'key of object in object storage'
        required: true
        schema:
          type: string
      responses:
        '200':
          description: OK
          content:
              image/jpeg:
                schema: 
                  type: string
                  format: binary
      x-yc-apigateway-integration:
        type: object_storage
        bucket: ${yandex_storage_bucket.faces_bucket.id}
        object: '{face}'
        presigned_redirect: false
        service_account_id: ${yandex_iam_service_account.sa.id}
        http_headers:
          'Content-Type': "image/jpeg"
          'Content-Disposition': 'attachment; filename="{face}.jpg"'
        operationId: static
        responses:
        '200':
          description: OK
          content:
              image/jpeg:
                schema: 
                  type: string
                  format: binary
  /original:
    get:
      parameters:
      - name: image
        in: query
        description: 'key of object in object storage'
        required: true
        schema:
          type: string
      responses:
        '200':
          description: OK
          content:
              image/jpeg:
                schema: 
                  type: string
                  format: binary
      x-yc-apigateway-integration:
        type: object_storage
        bucket: ${yandex_storage_bucket.photos_bucket.id}
        object: '{image}'
        presigned_redirect: false
        service_account_id: ${yandex_iam_service_account.sa.id}
        http_headers:
          'Content-Type': "image/jpeg"
          'Content-Disposition': 'attachment; filename="{image}.jpg"'
        operationId: static
        responses:
        '200':
          description: OK
          content:
              image/jpeg:
                schema: 
                  type: string
                  format: binary
EOT
}