variable "vpc_name" {
   description = "vpc name"
   type        = string
}

variable "cidr" {
   description = "vpc_cidr"
   type        = string
}

variable "bucket_name" {
   description = "S3 bucket name"
   type        = string
}

variable "sqs_queue_name" {
   description = "sqs queue name"
   type        = string
}

variable "dynamodb_table_name" {
   description = "dynamodb table name"
   type        = string
}

variable "alb_sq_name" {
   description = "ALB security group name"
   type        = string
}

variable "alb_name" {
   description = "alb name"
   type        = string
}

variable "target_group_name" {
   description = "target group name"
   type        = string
}

variable "instance_ami" {
   description = "target group name"
   type        = string
}

variable "instance_type" {
   description = "target group name"
   type        = string
}

variable "key_name" {
   description = "target group name"
   type        = string
}

variable "availability_zone" {
   description = "target group name"
   type        = string
}

variable "availability_zone2" {
   description = "target group name"
   type        = string
}

variable "instance_sg_name" {
   description = "target group name"
   type        = string
}