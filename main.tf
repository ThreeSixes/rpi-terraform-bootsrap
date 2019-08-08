# Raspberry Pi Terraform Bootstrap Provisioner (Tested with Raspbian Stretch).
# This is a run-once bootstrap Terraform provisioner for a Raspberry Pi.
# Provisioners by default run only at resource creation, additional runs without cleanup may introduce problems.
# https://www.terraform.io/docs/provisioners/index.html
locals{
  host_script_path = "/opt/terraform/scripts"
  host_template_path = "/opt/terraform/templates"
  ssh_timeout = "10s"
  default_sleep = "1s"
  ssh_private_key = "${path.module}/.ssh/id_rsa"
  ssh_public_key = "${path.module}/.ssh/id_rsa.pub"
}

/******************************************************************************************************
 * SSH KEY
 ******************************************************************************************************/
#generates a RSA private key for authentication
resource "tls_private_key" "rsa_private" {
  depends_on = ["null_resource.init"]
  algorithm = "RSA"
  rsa_bits  = 4096
}

#creates a local file id_rsa containing the actual private key in PEM Format
resource "local_file" "private_key" {
    count = 1
    content = "${tls_private_key.rsa_private.private_key_pem}"
    filename = "${local.ssh_private_key}"
}

#creates a local file id_rsa.pub containing the actual public key in openssh format
resource "local_file" "public_key" {
    count = 1
    content = "${tls_private_key.rsa_private.public_key_openssh}"
    filename = "${local.ssh_public_key}"
}

/******************************************************************************************************
 * INIT
 ******************************************************************************************************/

resource "null_resource" "init" {
  connection {
    type = "ssh"
    user = "${var.initial_user}"
    password = "${var.initial_password}"
    host = "${var.ip_adress}"
    timeout = "${local.ssh_timeout}"
  }

  provisioner "remote-exec" {
    inline = [
      "echo 'creating script folders'",
      "sudo mkdir -vp ${local.host_script_path}",
      "sudo mkdir -vp ${local.host_template_path}",
      "sudo chmod -R 777 /opt/terraform/",
    ]
  }
}

/******************************************************************************************************
 * COPY
 ******************************************************************************************************/

resource "null_resource" "copy" {
  depends_on = ["null_resource.init"]
  connection {
    type = "ssh"
    user = "${var.initial_user}"
    password = "${var.initial_password}"
    host = "${var.ip_adress}"
    timeout = "${local.ssh_timeout}"
  }

  provisioner "file" {
    source      = "${path.module}/scripts/"
    destination = "${local.host_script_path}"
  }

  provisioner "file" {
    source      = "${path.module}/templates/"
    destination = "${local.host_template_path}"
  }

  provisioner "remote-exec" {
    inline = [
      "echo 'copy ressources to host'",
    ]
  }
  provisioner "remote-exec" {
    when = "destroy"
    inline = [
      "echo 'deleting scripts and templates'",
      "rm -fr ${local.host_script_path}",
      "rm -fr ${local.host_template_path}",
    ]
  }
}

/******************************************************************************************************
 * ADDUSER
 ******************************************************************************************************/
resource "random_string" "password" {
  length = 24
  special = false
  min_upper = 8
  min_lower = 8
  min_numeric = 4
}

resource "null_resource" "adduser" {
  depends_on = ["null_resource.copy", "random_string.password"]

  connection {
    type = "ssh"
    user = "${var.initial_user}"
    password = "${var.initial_password}"
    host = "${var.ip_adress}"
    timeout = "${local.ssh_timeout}"
  }

  provisioner "remote-exec" {
    inline = [
      "sudo chmod +x ${local.host_script_path}/init_adduser.sh",
      "${local.host_script_path}/init_adduser.sh ${var.new_user} ${random_string.password.result} ${var.initial_user}",
    ]
  }

  provisioner "remote-exec" {
    when = "destroy"
    inline = [
      "sudo chmod +x ${local.host_script_path}/destroy_adduser.sh",
      "${local.host_script_path}/destroy_adduser.sh ${var.initial_user} ${var.initial_password} ${var.new_user}",
    ]
  }
}
/******************************************************************************************************
 * SSH COPY ID
 ******************************************************************************************************/
 # connects as new user & copies the public key to its /home/pi/.ssh/authorized_keys
resource "null_resource" "ssh-copy-id" {
  depends_on = ["null_resource.adduser", "local_file.public_key"]
  connection {
    type = "ssh"
    user = "${var.new_user}"
    password = "${random_string.password.result}"
    host = "${var.ip_adress}"
    timeout = "${local.ssh_timeout}"
  }

  provisioner "file" {
    source      = "${local.ssh_public_key}"
    destination = "/tmp/id_rsa.pub"
  }

  provisioner "remote-exec" {
    inline = [
      #create .ssh folder in /home/pi
      "mkdir -vp ~/.ssh",
      #write public key to /home/pi/.ssh/authorized_keys
      "cat /tmp/id_rsa.pub >> ~/.ssh/authorized_keys",
      #delete tmp file
      "sudo rm -fv /tmp/id_rsa.pub",
    ]
  }
}

/******************************************************************************************************
 * HOSTNAME
 ******************************************************************************************************/

resource "null_resource" "hostname" {
  depends_on = ["null_resource.ssh-copy-id"]

  connection {
    type = "ssh"
    private_key = "${tls_private_key.rsa_private.private_key_pem}"
    user = "${var.new_user}"
    host = "${var.ip_adress}"
    timeout = "${local.ssh_timeout}"
  }

  provisioner "remote-exec" {
    inline = [
      "sudo chmod +x ${local.host_script_path}/init_hostname.sh",
      "sudo ${local.host_script_path}/init_hostname.sh ${var.hostname}",
    ]
  }

  provisioner "remote-exec" {
    when = "destroy"
    inline = [
      "sudo chmod +x ${local.host_script_path}/destroy_hostname.sh",
      "sudo ${local.host_script_path}/destroy_hostname.sh",
    ]
  }
}

/******************************************************************************************************
 * DISABLESWAP
 ******************************************************************************************************/

resource "null_resource" "disableswap" {
  depends_on = ["null_resource.ssh-copy-id"]

  connection {
    type = "ssh"
    private_key = "${tls_private_key.rsa_private.private_key_pem}"
    user = "${var.new_user}"
    host = "${var.ip_adress}"
    timeout = "${local.ssh_timeout}"
  }

  provisioner "remote-exec" {
    inline = [
      "sudo chmod +x ${local.host_script_path}/init_disableswap.sh",
      "sudo ${local.host_script_path}/init_disableswap.sh",
    ]
  }

  provisioner "remote-exec" {
    when = "destroy"
    inline = [
      "sudo chmod +x ${local.host_script_path}/destroy_disableswap.sh",
      "sudo ${local.host_script_path}/destroy_disableswap.sh",
    ]
  }
}

/******************************************************************************************************
 * TIMEZONE
 ******************************************************************************************************/

resource "null_resource" "timezone" {
  depends_on = ["null_resource.ssh-copy-id"]

  connection {
    type = "ssh"
    private_key = "${tls_private_key.rsa_private.private_key_pem}"
    user = "${var.new_user}"
    host = "${var.ip_adress}"
    timeout = "${local.ssh_timeout}"
  }

  provisioner "remote-exec" {
    inline = [
      "sudo chmod +x ${local.host_script_path}/init_timezone.sh",
      "sudo ${local.host_script_path}/init_timezone.sh ${var.timezone}",
    ]
  }

  provisioner "remote-exec" {
    when = "destroy"
    inline = [
      "sudo chmod +x ${local.host_script_path}/destroy_timezone.sh",
      "sudo ${local.host_script_path}/destroy_timezone.sh",
    ]
  }
}


/******************************************************************************************************
 * UPDATE
 ******************************************************************************************************/

resource "null_resource" "update" {
  depends_on = ["null_resource.timezone"]

  connection {
    type = "ssh"
    private_key = "${tls_private_key.rsa_private.private_key_pem}"
    user = "${var.new_user}"
    host = "${var.ip_adress}"
    timeout = "${local.ssh_timeout}"
  }

  provisioner "remote-exec" {
    inline = [
      "sudo chmod +x ${local.host_script_path}/init_update.sh",
      "sudo ${local.host_script_path}/init_update.sh",
    ]
  }
}

/******************************************************************************************************
 * TOOLS
 ******************************************************************************************************/

resource "null_resource" "tools" {
  depends_on = ["null_resource.update"]

  connection {
    type = "ssh"
    private_key = "${tls_private_key.rsa_private.private_key_pem}"
    user = "${var.new_user}"
    host = "${var.ip_adress}"
    timeout = "${local.ssh_timeout}"
  }

  provisioner "remote-exec" {
    inline = [
      "sudo chmod +x ${local.host_script_path}/init_tools.sh",
      "sudo ${local.host_script_path}/init_tools.sh",
    ]
  }
}

/******************************************************************************************************
 * REBOOT
 ******************************************************************************************************/
/*
  Rebooting is tricky since Terraform 0.11.3
  this is the only solution I got working for Raspian adding another 80s
  and 2 Ressources only for Rebooting, but without it Docker install is running in some
  Issues
  see https://github.com/hashicorp/terraform/issues/17844
*/
resource "null_resource" "reboot" {
  depends_on = ["null_resource.tools"]

  connection {
    type = "ssh"
    private_key = "${tls_private_key.rsa_private.private_key_pem}"
    user = "${var.new_user}"
    host = "${var.ip_adress}"
    timeout = "${local.ssh_timeout}"
  }

  provisioner "remote-exec" {
    inline = [
      "echo '--------------------------------------------------------'",
      "echo '------------      R E B O O T - H A C K    -------------'",
      "echo '------------------------ 90s ---------------------------'",
      #schedule reboot in 1min
      "sudo shutdown -r &",
      #2sec sleep for adding the reboot securely
      "sleep 2"
    ]
  }
}


resource "null_resource" "reboot_wait" {
  depends_on = ["null_resource.reboot"]

  #!waits 90s - only works on Windows
  #90s was best for my setup so reboot is under 30s - but it can take longer
  #80s would even work but i added 10s for safety
  provisioner "local-exec" {
    command     = "Start-Sleep 90",
    interpreter = ["PowerShell", "-Command"]
  }
}
