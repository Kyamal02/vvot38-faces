variable "bot_key" {
  type        = string
  description = "Telegram Bot API Key"
}

variable "zone" {
  type        = string
  description = "Region zone code"
}

variable "folder_id" {
  type        = string
  description = "Cloud Folder Id"
}

variable "folder_name" {
  type        = string
  description = "Cloud Folder Name"
}

variable "cloud_id" {
  type        = string
  description = "Cloud Id"
}

variable "mem" {
  type        = number
  description = "Function memory"
}