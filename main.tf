
resource "aws_vpc" "main" { //Este recurso crea la VPC principal
  cidr_block         = "10.0.0.0/16"
  enable_dns_support = true

  tags = {
    Name = "Project VPC"
  }
}
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "Project Internet Gateway"
  }
}
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "Project Public Route Table"
  }
}
resource "aws_route_table_association" "public" {
  count = length(var.public_subnet_cidrs)

  subnet_id      = aws_subnet.public_subnets[count.index].id
  route_table_id = aws_route_table.public.id
}
resource "aws_subnet" "public_subnets" {
  count      = length(var.public_subnet_cidrs) // Conservar las tres subredes publicas existentes.
  vpc_id     = aws_vpc.main.id
  cidr_block = element(var.public_subnet_cidrs, count.index)
  availability_zone = element(
    ["us-east-1a", "us-east-1b", "us-east-1c"],
    count.index
  )
  map_public_ip_on_launch = true
  tags = {
    Name = "Public Subnet ${count.index + 1}" // para contabilizar el nombre con las subredes que hay en la lista
  }
}

resource "aws_subnet" "private_subnets" {
  count                   = length(var.private_subnet_cidrs)
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.private_subnet_cidrs[count.index]
  availability_zone       = aws_subnet.public_subnets[count.index].availability_zone
  map_public_ip_on_launch = false

  tags = {
    Name = "Private Subnet ${count.index + 1}"
  }
}

# Asociación explícita: la privada no hereda una ruta pública de la tabla principal.
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "Project Private Route Table" }
}

resource "aws_route_table_association" "private" {
  count          = length(var.private_subnet_cidrs)
  subnet_id      = aws_subnet.private_subnets[count.index].id
  route_table_id = aws_route_table.private.id
}


resource "aws_security_group" "web_sg" {
  name   = "web-security-group"
  vpc_id = aws_vpc.main.id

  //trafico de entrada para SSH desde la IP publica del operador
  ingress {
    description = "SSH desde la IPv4 publica del operador"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.ssh_allowed_cidr] //aqui estamos gestionando la variable que nos solicita la ip publica del operador para poder hacer SSH a la instancia
  }

  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  //trafico de salida para todo el trafico
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

// Este recurso crea un grupo de autoescalado con una plantilla de lanzamiento es la ami que utilizaremos
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }
}

resource "aws_key_pair" "web" {
  key_name_prefix = "project-asg-"
  public_key      = trimspace(file(pathexpand(var.ssh_public_key_path)))
}

resource "aws_launch_template" "web" {
  name_prefix   = "web-template-"
  image_id      = data.aws_ami.amazon_linux.id
  instance_type = var.instance_type
  key_name      = aws_key_pair.web.key_name

  network_interfaces {
    device_index                = 0
    associate_public_ip_address = true
    delete_on_termination       = true
    security_groups             = [aws_security_group.web_sg.id]
  }

  user_data = base64encode(<<-EOF
    #!/bin/bash
    set -euo pipefail
    # Reintentar si la red o los repositorios tardan en estar disponibles.
    for attempt in $(seq 1 10); do
      if dnf install -y httpd; then break; fi
      sleep 15
    done
    rpm -q httpd
    printf '<!doctype html><html lang="es"><meta charset="utf-8"><title>Project ASG</title><h1>Apache en Amazon Linux 2023</h1><p>Hostname: %s</p></html>\n' "$(hostname)" > /var/www/html/index.html
    systemctl enable --now httpd
    curl --fail --retry 5 --retry-delay 2 http://localhost/
  EOF
  )
}

resource "aws_autoscaling_group" "web" {
  name = "project-asg"

  min_size         = 1
  max_size         = 3
  desired_capacity = 2

  //Preservar la tercera subred existente, usando dos AZ para este laboratorio.
  vpc_zone_identifier = slice(aws_subnet.public_subnets[*].id, 0, 2)

  launch_template {
    id      = aws_launch_template.web.id
    version = tostring(aws_launch_template.web.latest_version)
  }

  target_group_arns         = [aws_lb_target_group.web.arn]
  health_check_type         = "ELB"
  health_check_grace_period = 300

  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 50
      max_healthy_percentage = 100
      instance_warmup        = 180
      skip_matching          = true
    }
  }

  // No arrancar instancias antes de que las rutas esten disponibles.
  depends_on = [aws_route_table_association.public, aws_lb_listener.http]

  lifecycle {
    precondition {
      condition     = aws_subnet.public_subnets[0].availability_zone != aws_subnet.public_subnets[1].availability_zone
      error_message = "Las dos subredes del ASG deben estar en AZ diferentes."
    }
  }
}



// rds

resource "aws_db_subnet_group" "education" {
  name        = "education" //nombre de la subred del grupo de base de datos
  description = "Subredes para la base de datos RDS"
  subnet_ids  = aws_subnet.private_subnets[*].id
  tags = {
    Name = "Education"
  }
}

resource "aws_db_parameter_group" "education" {
  name   = "education"
  family = "postgres18"

  parameter {
    name  = "log_connections"
    value = "all"
  }
}

resource "aws_security_group" "rds" {
  name        = "rds-security-group"
  description = "Grupo de seguridad para RDS"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "PostgreSQL desde EC2"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.web_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_db_instance" "education" {
  identifier             = "education"
  instance_class         = "db.t3.micro"
  allocated_storage      = 5
  engine                 = "postgres"
  engine_version         = "18.3"
  username               = "edu"
  password               = var.db_password
  db_subnet_group_name   = aws_db_subnet_group.education.name
  vpc_security_group_ids = [aws_security_group.rds.id] //conectar con la vpc y el grupo de seguridad que creamos para la base de datos
  parameter_group_name   = aws_db_parameter_group.education.name
  publicly_accessible    = false
  skip_final_snapshot    = true
}
