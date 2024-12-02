terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">=5.55"
    }
  }
  backend "s3" {
    bucket = "shachar-terraform-bucket"
    key    = "tfstate.json"
    region = "eu-north-1"
    # optional: dynamodb_table = "<table-name>"
  }

  required_version = ">= 1.7.0"
}

provider "aws" {
  region  = "eu-north-1"  # Use variable for region
  profile = "default"   # Change in case you want to work with another AWS account profile
}

module "vpc" {
  source = "terraform-aws-modules/vpc/aws"

  name = var.vpc_name
  cidr = var.cidr

  azs             = ["eu-north-1a", "eu-north-1b"]
  public_subnets  = ["10.0.1.0/24", "10.0.2.0/24"]
}

resource "aws_s3_bucket" "polybot_bucket" {
  bucket = var.bucket_name
}

resource "aws_sqs_queue" "standard_queue" {
  name = var.sqs_queue_name
}

resource "aws_dynamodb_table" "simple_dynamodb_table" {
  name         = var.dynamodb_table_name
  billing_mode = "PAY_PER_REQUEST"

  hash_key     = "prediction_id"

  attribute {
    name = "prediction_id"
    type = "S"
  }
}

resource "aws_security_group" "alb_polybot_sg" {
  name        = var.alb_sq_name
  description = "Security group for Application Load Balancer"
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 8443
    to_port     = 8443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_lb" "polybot_alb" {
  name               = var.alb_name
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_polybot_sg.id]
  subnets            = module.vpc.public_subnets
}

resource "aws_lb_target_group" "polybot_target_group" {
  name     = var.target_group_name
  port     = 8443
  protocol = "HTTP"
  vpc_id   = module.vpc.vpc_id

  health_check {
    path                = "/"
    interval            = 30
    timeout             = 5
    healthy_threshold  = 2
    unhealthy_threshold = 2
  }
}

resource "aws_acm_certificate" "certificate_manager" {
  domain_name       = "shachar.online"
  validation_method = "DNS"
  subject_alternative_names = [
    "*.shachar.online"
  ]
}

resource "aws_route53_record" "cert_validation_record1" {
  zone_id = data.aws_route53_zone.hosted_zone.zone_id
  name     = tolist(aws_acm_certificate.certificate_manager.domain_validation_options)[0].resource_record_name
  type     = tolist(aws_acm_certificate.certificate_manager.domain_validation_options)[0].resource_record_type
  ttl      = 60

  records = [tolist(aws_acm_certificate.certificate_manager.domain_validation_options)[0].resource_record_value]
}

resource "aws_route53_record" "alb_record" {
  zone_id = data.aws_route53_zone.hosted_zone.zone_id
  name     = "shachar.online"
  type     = "A"

  alias {
    name                   = aws_lb.polybot_alb.dns_name
    zone_id                = aws_lb.polybot_alb.zone_id
    evaluate_target_health = true
  }
}

resource "aws_lb_listener" "https_listener" {
  load_balancer_arn = aws_lb.polybot_alb.arn
  port              = 8443
  protocol          = "HTTPS"

  ssl_policy        = "ELBSecurityPolicy-2016-08"
  certificate_arn   = aws_acm_certificate.certificate_manager.arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.polybot_target_group.arn
  }
}

resource "aws_security_group" "instance_sg" {
  name        = var.instance_sg_name
  description = "Security group for EC2 instance"
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 8443
    to_port     = 8443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

   ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port              = 80
    to_port                = 80
    protocol               = "tcp"
    security_groups        = [aws_security_group.alb_polybot_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_iam_policy" "my_policy" {
  name        = "MyPolicy"
  description = "Policy to allow access to S3, DynamoDB, and SQS"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:*"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "dynamodb:*"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "sqs:*"
        ]
        Resource = "*"
      },
      {
        "Effect": "Allow",
        "Action": "secretsmanager:GetSecretValue",
        "Resource": "*"
      }
    ]
  })
}

resource "aws_iam_role" "polybot_role" {
  name               = "polybot_role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action    = "sts:AssumeRole"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
        Effect    = "Allow"
        Sid       = ""
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "my_policy_attachment" {
  policy_arn = aws_iam_policy.my_policy.arn
  role       = aws_iam_role.polybot_role.name
}

resource "aws_iam_instance_profile" "polybot_instance_profile" {
  name = "polybot_instance_profile"
  role = aws_iam_role.polybot_role.name
}


resource "aws_instance" "polybot1" {
  ami             = var.instance_ami
  instance_type   = var.instance_type  # Use variable for instance type
  key_name        = var.key_name
  vpc_security_group_ids = [aws_security_group.instance_sg.id]
  availability_zone = var.availability_zone
  subnet_id   = module.vpc.public_subnets[0]
  associate_public_ip_address = true
  iam_instance_profile         = aws_iam_instance_profile.polybot_instance_profile.name
  tags = {
    Name = "polybot1"
  }
}
output "polybot1_public_ip" {
  value = aws_instance.polybot1.public_ip
}


resource "aws_instance" "polybot2" {
  ami             = var.instance_ami
  instance_type   = var.instance_type  # Use variable for instance type
  key_name        = var.key_name
  vpc_security_group_ids = [aws_security_group.instance_sg.id]
  availability_zone = var.availability_zone2
  subnet_id   = module.vpc.public_subnets[1]
  associate_public_ip_address = true
  iam_instance_profile         = aws_iam_instance_profile.polybot_instance_profile.name
  tags = {
    Name = "polybot2"
  }
}

output "polybot2_public_ip" {
  value = aws_instance.polybot2.public_ip
}

resource "aws_lb_target_group_attachment" "attachment1" {
  target_group_arn = aws_lb_target_group.polybot_target_group.arn
  target_id        = aws_instance.polybot1.id
  port             = 8443
}

resource "aws_lb_target_group_attachment" "attachment2" {
  target_group_arn = aws_lb_target_group.polybot_target_group.arn
  target_id        = aws_instance.polybot2.id
  port             = 8443
}

resource "aws_launch_template" "yolo5_template" {
  name_prefix   = "yolo5-template-"
  image_id      = var.instance_ami
  instance_type = var.yolo5_type

  iam_instance_profile {
    name = aws_iam_instance_profile.polybot_instance_profile.name
  }

  key_name = var.key_name

  user_data = base64encode(<<-EOF
              #!/bin/bash
              apt-get update -y
              apt-get install docker.io -y
              systemctl start docker
              systemctl enable docker
              docker pull shacharavraham/yolo5
              sleep 60
              sudo docker run -d -p 8443:8443 --restart always -e BUCKET_NAME="shachar-polybot-image-bucket" -e SQS_QUEUE_NAME="polybot-queue" -e polybot-table="polybot-table" shacharavraham/yolo5:latest
              EOF
  )

  lifecycle {
    create_before_destroy = true
  }

  network_interfaces {
    associate_public_ip_address = true
    security_groups = [aws_security_group.instance_sg.id]
  }
}

resource "aws_autoscaling_group" "yolo5_asg" {
  desired_capacity     = 1
  max_size             = 2
  min_size             = 1

  launch_template {
    id      = aws_launch_template.yolo5_template.id
    version = "$Latest"
  }

  vpc_zone_identifier = module.vpc.public_subnets

  health_check_type         = "EC2"
  health_check_grace_period = 300
  force_delete               = true

  tag {
    key                 = "Name"
    value               = "yolo5-instance"
    propagate_at_launch = true
  }
}

resource "aws_autoscaling_policy" "scale_up" {
  name                   = "scale_up"
  scaling_adjustment      = 1
  adjustment_type        = "ChangeInCapacity"
  autoscaling_group_name = aws_autoscaling_group.yolo5_asg.name
}

resource "aws_autoscaling_policy" "scale_down" {
  name                   = "scale_down"
  scaling_adjustment      = -1
  adjustment_type        = "ChangeInCapacity"
  autoscaling_group_name = aws_autoscaling_group.yolo5_asg.name
}

resource "aws_cloudwatch_metric_alarm" "cpu_high" {
  alarm_name          = "cpu_high_alarm"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name        = "CPUUtilization"
  namespace          = "AWS/EC2"
  period             = 60
  statistic          = "Average"
  threshold          = 60

  alarm_actions = [aws_autoscaling_policy.scale_up.arn]

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.yolo5_asg.name
  }
}

resource "aws_cloudwatch_metric_alarm" "cpu_low" {
  alarm_name          = "cpu_low_alarm"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 1
  metric_name        = "CPUUtilization"
  namespace          = "AWS/EC2"
  period             = 60
  statistic          = "Average"
  threshold          = 20

  alarm_actions = [aws_autoscaling_policy.scale_down.arn]

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.yolo5_asg.name
  }
}







