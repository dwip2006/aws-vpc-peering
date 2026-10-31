output "public_ec2_ip" {
  value = aws_instance.public.public_ip
}

output "private_a_ip" {
  value = aws_instance.private_a.private_ip
}

output "private_b_ip" {
  value = aws_instance.private_b.private_ip
}

output "peering_connection_id" {
  value = aws_vpc_peering_connection.ab.id
}
