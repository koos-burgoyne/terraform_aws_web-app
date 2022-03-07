terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 3.74"
    }
  }

  required_version = ">= 0.14.9"
}

provider "aws" {
  profile = "default"
  region  = "us-west-2"

  # Tags that are applied to all components
  default_tags {
    tags = {
      App = "django_rds_app"
    }
  }
}

# Default VPC
data "aws_vpc" "default" {
  default = true
}
data "aws_subnet_ids" "default" {
  vpc_id = data.aws_vpc.default.id
}

# --- S3 Bucket ---
# Creating the bucket
resource "aws_s3_bucket" "web-app" {
  force_destroy = true
}
# Granting the Bucket Access
resource "aws_s3_bucket_public_access_block" "publicaccess" {
  bucket              = aws_s3_bucket.web-app.id
  block_public_acls   = true
  block_public_policy = true
}

resource "aws_s3_bucket_object" "web-app-bucket-object" {
  bucket = aws_s3_bucket.web-app.id
  key    = var.docker_img_tar_file
  source = "../${var.docker_img_tar_file}"

  # This gets the md5 checksum of the image file and checks to see if it has
  # changed since the last apply
  etag = filemd5("../${var.docker_img_tar_file}")
}

# S3 access
resource "aws_iam_policy" "ec2_s3_policy" {
  description = "Policy to give s3 permission to ec2"
  policy      = file("policies/s3-policy.json")
}
resource "aws_iam_role" "ec2_s3_role" {
  assume_role_policy = file("roles/s3-role.json")
}
resource "aws_iam_role_policy_attachment" "ec2_s3_role_policy_attachment" {
  role       = aws_iam_role.ec2_s3_role.name
  policy_arn = aws_iam_policy.ec2_s3_policy.arn
}
resource "aws_iam_instance_profile" "ec2_s3_profile" {
  role = aws_iam_role.ec2_s3_role.name
}

# --- Security Groups ---
resource "aws_security_group" "RDS" {
  description = "allow ssh and http traffic"
  ingress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    security_groups = [aws_security_group.http-ssh.id]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "http-ssh" {
  description = "allow ssh and http traffic"
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 80
    to_port     = 80
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

# --- RDS Instance ---
resource "aws_db_instance" "db-resource" {
  name                    = "dj_app_db"
  username                = var.db_username
  password                = var.db_password
  port                    = "5432"
  engine                  = "postgres"
  engine_version          = "12.9"
  instance_class          = "db.t2.micro"
  allocated_storage       = "20"
  storage_encrypted       = false
  vpc_security_group_ids  = [aws_security_group.RDS.id]
  multi_az                = false
  storage_type            = "gp2"
  publicly_accessible     = false
  backup_retention_period = 7
  skip_final_snapshot     = true
}

# --- EC2 Instance ---
resource "aws_launch_configuration" "app-server" {
  ami                    = var.ami_al2_ecs
  instance_type          = "t2.micro"
  key_name               = "aws_ras01"
  vpc_security_group_ids = [aws_security_group.http-ssh.id]
  iam_instance_profile   = aws_iam_instance_profile.ec2_s3_profile.name

  depends_on = [
    aws_s3_bucket_object.web-app-bucket-object,
    aws_db_instance.db-resource
  ]

  user_data = <<EOF
#!/bin/bash
sudo yum update -y
sudo yum install -y unzip

# Install aws cli
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install

# Fetch docker image
aws s3 cp s3://${aws_s3_bucket.web-app.id}/${aws_s3_bucket_object.web-app-bucket-object.id} .

# Load and run image
docker load -i ./${aws_s3_bucket_object.web-app-bucket-object.id}
docker run -dp 80:8000 \
  --env RDS_DB_NAME=${aws_db_instance.db-resource.name} \
  --env RDS_HOSTNAME=${aws_db_instance.db-resource.address} \
  --env RDS_PORT=${aws_db_instance.db-resource.port} \
  --env RDS_USERNAME=${var.db_username} \
  --env RDS_PASSWORD=${var.db_password} \
  --name ${var.app_container_name} \
  ${var.docker_img_tag}
docker exec ${var.app_container_name} python manage.py collectstatic

# Cleanup
rm awscliv2.zip
rm ${aws_s3_bucket_object.web-app-bucket-object.id}

docker exec <container name> python manage.py migrate
docker exec -it ${var.app_container_name} bash

  EOF
}

# --- Load Balancing ---
resource "aws_lb" "lb_main" {
  load_balancer_type = "application"
  security_groups    = [aws_security_group.http-ssh.id]
  subnets            = data.aws_subnet_ids.default.ids
}

resource "aws_lb_target_group" "default-target-group" {
  port     = 80
  protocol = "HTTP"
  vpc_id   = data.aws_vpc.default.id

  health_check {
    path                = "/"
    port                = "traffic-port"
    healthy_threshold   = 5
    unhealthy_threshold = 2
    timeout             = 2
    interval            = 5
    matcher             = "200"
  }
}

resource "aws_lb_listener" "your_lb_listener" {
  load_balancer_arn = aws_lb.lb_main.id
  port              = 80
  protocol          = "HTTP"
  depends_on = [
    aws_lb_target_group.default-target-group
  ]

  # By default, return a simple 404 page
  default_action {
    type = "fixed-response"
    fixed_response {
      content_type = "text/plain"
      message_body = "404: page not found"
      status_code  = 404
    }
  }
}
resource "aws_lb_listener_rule" "lblr-default" {
  listener_arn = aws_lb_listener.your_lb_listener.arn

  condition {
    path_pattern {
      values = ["*"]
    }
  }
  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.default-target-group.arn
  }
}

# --- Auto Scaling ---
resource "aws_autoscaling_group" "autoscaler" {
  launch_configuration = aws_launch_configuration.app-server.name
  vpc_zone_identifier  = data.aws_subnet_ids.default.ids
  target_group_arns    = [aws_lb_target_group.default-target-group.arn]
  health_check_type    = "ELB"
  min_size             = 1
  max_size             = 10
  desired_capacity     = 1
}