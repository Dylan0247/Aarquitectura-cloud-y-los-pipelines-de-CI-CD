

variable "aws_region" {
  description = "Región de AWS donde se desplegará la red o instancias. us-east-1 es Norte de Virginia."
  type        = string
  default     = "us-east-1" //Escojo esta region porque es la que me proporciona el laboratorio
}

variable "public_subnet_cidrs" {
  type        = list(string)
  description = "Public Subnet CIDR values"
  default     = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"] // Conservar las tres existentes; el ASG usa las dos primeras.

  validation {
    condition     = length(var.public_subnet_cidrs) >= 2
    error_message = "Se necesitan al menos dos subredes publicas."
  }
}


// variable para solicitar una ip publica mediante SSH
variable "ssh_allowed_cidr" {
  description = "IPv4 publica del equipo WSL en formato x.x.x.x/32. Sin valor por defecto."
  type        = string
  nullable    = false
  validation {
    condition     = can(cidrnetmask(var.ssh_allowed_cidr)) && can(regex("^[0-9.]+/32$", var.ssh_allowed_cidr)) && var.ssh_allowed_cidr != "0.0.0.0/32"
    error_message = "SSH requiere una unica IPv4 valida con /32; no se admiten redes abiertas."
  }
}


// Esta variables es para indicar donde tener alojada la clave que nos solicita la variable ssh_allowed_cidr
variable "ssh_public_key_path" {
  description = "Ruta local al archivo .pub OpenSSH. Nunca indicar la clave privada."
  type        = string
  default     = "~/.ssh/project-asg.pub"
  validation {
    condition     = can(regex("^(ssh-ed25519|ssh-rsa|ecdsa-sha2-nistp(256|384|521)) [A-Za-z0-9+/=]+( .*)?$", trimspace(file(pathexpand(var.ssh_public_key_path)))))
    error_message = "La ruta debe contener una clave publica OpenSSH valida; no una clave privada."
  }
}

variable "private_subnet_cidrs" {
  type        = list(string)
  description = "CIDR de las dos subredes privadas para RDS."
  default     = ["10.0.4.0/24", "10.0.5.0/24"]

  validation {
    condition     = length(var.private_subnet_cidrs) == 2
    error_message = "RDS requiere dos subredes privadas en esta configuracion."
  }
}

variable "project_name" {
  description = "Nombre del proyecto. Se usa en tags."
  type        = string
  default     = "Despliegue Automatizado de Infraestructura en AWS"
}

variable "environment" {
  description = "Entorno (lab, dev, prod...)."
  type        = string
  default     = "lab"
}

variable "instance_name" {
  description = "Valor de la etiqueta Name de la instancia EC2."
  type        = string
  default     = "tf-lab-ec2"
}

// Variables EC2 para el Auto Scaling Group (ASG)
variable "instance_type" {
  description = "Tipo de instancia EC2"
  type        = string
  default     = "t3.micro"
}

// Variable minima que hay que tener para la instancia
variable "min_size" {
  description = "Número mínimo de instancias"
  type        = number
  default     = 1
}

// variable maxima que hay que tener para la instancia
variable "max_size" {
  description = "Número máximo de instancias"
  type        = number
  default     = 3
}

// Variable deseada que hay que tener para la instancia
variable "desired_capacity" {
  description = "Número deseado de instancias"
  type        = number
  default     = 2
}


//rds
variable "db_password" {
  description = "RDS root user password"
  type        = string
  sensitive   = true
}
