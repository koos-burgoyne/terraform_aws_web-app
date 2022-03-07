output "ec2_ip" {
  value = aws_lb.lb_main.dns_name
}
output "db_host_name" {
  value = aws_db_instance.db-resource.address
}