variable "ami_al2_ecs" {
  description = "Amazon Linux 2 with ECS. Latest as of 2022-02-11"
  type        = string
  default     = "ami-02b05e04df16de7a9"
}

# Default values to be set
variable "docker_img_tar_file" {
  description = "docker image tar file"
  type        = string
  default     = "<insert name here>"
}
variable "docker_img_tag" {
  description = "Tag used for the docker image"
  type        = string
  default     = "<insert tag here>"
}
variable "app_container_name" {
  description = "Name of running app container"
  type        = string
  default     = "<insert container name here>"
}

# Either enter when prompted or set environment variables
variable "db_username" {
  type  = string
}
variable "db_password" {
  type = string
}

