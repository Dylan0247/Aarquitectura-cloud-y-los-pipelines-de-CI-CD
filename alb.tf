// Entrada HTTP publica; las EC2 solo aceptan HTTP desde este grupo.
resource "aws_security_group" "alb" {
  name        = "project-alb-security-group"
  description = "HTTP publico hacia el ALB"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTP desde Internet"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "HTTP y comprobaciones de salud dentro de la VPC"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.main.cidr_block]
  }
}

resource "aws_lb" "web" {
  name               = "project-web-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = slice(aws_subnet.public_subnets[*].id, 0, 2)

  depends_on = [aws_route_table_association.public]
}

// El ASG registra y retira sus instancias automaticamente en este grupo.
resource "aws_lb_target_group" "web" {
  name        = "project-web-targets"
  port        = 80
  protocol    = "HTTP"
  target_type = "instance"
  vpc_id      = aws_vpc.main.id

  health_check {
    enabled             = true
    path                = "/"
    protocol            = "HTTP"
    port                = "traffic-port"
    matcher             = "200"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }
}

// Recibe las peticiones y las envia al grupo de destinos.
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.web.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web.arn
  }
}
