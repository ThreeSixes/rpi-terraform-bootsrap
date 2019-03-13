//lokale Variablen um so gut wie möglich DRY zu folgen
locals{
  script_path = "${path.module}/scripts"
  tmp_path = "/tmp"
  init_script = "init_update.sh"
  ssh_timeout = "10s"
  ssh_user = "pi"
  default_sleep = "1s"
}

resource "null_resource" "update" {
  connection {
    type = "ssh"
    private_key = "${file("${var.private_key_path}")}"
    user = "${local.ssh_user}"
    host = "${var.ip_adress}"
    timeout = "${local.ssh_timeout}"
  }
  
  #You cannot pass any arguments to scripts using the script or scripts arguments to this provisioner. 
  #If you want to specify arguments, upload the script with the file provisioner and then use inline to call it.

  provisioner "file" {
    source      = "${local.script_path}/${local.init_script}"
    destination = "${local.tmp_path}/${local.init_script}"
  }

  provisioner "remote-exec" {
    inline = [
      "sleep ${local.default_sleep}",
      "if [ ! -f ${local.tmp_path}/${local.init_script} ]; then echo '${local.tmp_path}/${local.init_script} not found!'; else echo '${local.tmp_path}/${local.init_script} found'; fi",
      #make script executable
      "chmod -v +x ${local.tmp_path}/${local.init_script}",
      #execute it
      "${local.tmp_path}/${local.init_script}",
    ]
  }
}