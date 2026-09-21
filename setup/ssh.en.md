# SSH access and port forwarding

[中文](ssh.md) | English

Create the VMs using the [Terraform guide](terraform.en.md) first. Run the following commands on your **Mac**. Replace all address and username placeholders with your own values.

## 1. Find the connection details

Use Azure CLI to inspect the VM connection details:

```zsh
az vm list -d --resource-group "<resource-group>" \
  --query '[].{Name:name,User:osProfile.adminUsername,PublicIP:publicIps,PrivateIP:privateIps,State:powerState}' \
  --output table
```

SSH uses the VM's public IP, the `admin_username` from Terraform, and the private key matching the configured public key.
Terraform has already installed the public key, so there is no need to upload it again.

## 2. Configure SSH aliases

Open `~/.ssh/config`, creating it if necessary. Replace the placeholders below before adding the entries. If a Host already exists, update its entry without overwriting other hosts.

```sshconfig
Host streamify-kafka
    HostName <kafka-public-ip>
    User <vm-user>
    IdentityFile ~/.ssh/<private-key-file>
    IdentitiesOnly yes

Host streamify-airflow
    HostName <airflow-public-ip>
    User <vm-user>
    IdentityFile ~/.ssh/<private-key-file>
    IdentitiesOnly yes

Host streamify-spark streamify-spark-master
    HostName <spark-master-public-ip>
    User <vm-user>
    IdentityFile ~/.ssh/<private-key-file>
    IdentitiesOnly yes

Host streamify-spark-worker-1
    HostName <spark-worker-1-public-ip>
    User <vm-user>
    IdentityFile ~/.ssh/<private-key-file>
    IdentitiesOnly yes

Host streamify-spark-worker-2
    HostName <spark-worker-2-public-ip>
    User <vm-user>
    IdentityFile ~/.ssh/<private-key-file>
    IdentitiesOnly yes
```

`IdentityFile` points to the private key, not the `.pub` file. Replace the filename below and set permissions:

```zsh
chmod 700 ~/.ssh
chmod 600 ~/.ssh/config
chmod 600 ~/.ssh/<private-key-file>
```

## 3. Connect

Run one command at a time. Use `exit` to return to your Mac:

```zsh
ssh streamify-kafka
ssh streamify-airflow
ssh streamify-spark
ssh streamify-spark-worker-1
ssh streamify-spark-worker-2
```

`streamify-spark` and `streamify-spark-master` refer to the same Spark master.
Check the host fingerprint before accepting a first connection.

The public IP used by SSH must match `admin_source_cidr` in `terraform.tfvars`.
An HTTP proxy may not route SSH traffic. When using a VPN, check the terminal's route.
If the exit IP changes, update the variable and review the Terraform plan before applying it.

## 4. Open the web UIs

Once a service is running, start its tunnel on your Mac and open the local URL in a browser.
Forwarding lasts only as long as the SSH connection. Closing the terminal or pressing `Ctrl+C` ends it.

Airflow:

```zsh
ssh -N -o ExitOnForwardFailure=yes -L 127.0.0.1:8080:127.0.0.1:8080 streamify-airflow
```

Open `http://localhost:8080`.

Spark master, using local port 8082 to avoid a conflict with Airflow:

```zsh
ssh -N -o ExitOnForwardFailure=yes -L 127.0.0.1:8082:127.0.0.1:8080 streamify-spark
```

Open `http://localhost:8082`.

Kafka Control Center:

```zsh
ssh -N -o ExitOnForwardFailure=yes -L 127.0.0.1:9021:127.0.0.1:9021 streamify-kafka
```

Open `http://localhost:9021`. Broker port 9092 handles messages; it is not a web page.

## 5. Public and private addresses

Your Mac connects through public IPs. Traffic between VMs uses private IPs, such as `<kafka-private-ip>:9092` for Spark to reach Kafka.
While the static public IP resource is retained, a normal restart or deallocation does not change it. Query the addresses again after deleting and rebuilding resources.

Keep actual addresses and keys in your own SSH configuration, not in documentation.
