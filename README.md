# VProfile AWS — Terraform & Ansible

The entire project is in the same folder. **No roles, no scripts folder, no Python files, and no Terraform variables, modules, or loops.**

| File | Purpose |
|---|---|
| `main.tf` | Provisions AWS infrastructure, installs Ansible on app01, uploads files, and runs the playbook automatically |
| `inventory.ini` | The four machines and their IP addresses |
| `playbook.yml` | All service provisioning and application setup tasks in order, contained in a single file |
| `ansible.cfg` | Two lines to select the inventory file |
| `keys/` | Admin key for your local machine, and the managed key used by app01 to manage the rest |

## Project Architecture

```text
Your Machine --SSH--> app01: Tomcat + Ansible controller (10.0.1.10)
                      |--SSH--> db01: MariaDB   (10.0.2.40)
                      |--SSH--> mc01: Memcached (10.0.2.20)
                      |--SSH--> rmq01: RabbitMQ (10.0.2.30)

Browser --> ALB:80 --> app01:8080 --> The Three Services
Private Services --> NAT Gateway --> Internet for downloading packages
```

Four `t3.micro` EC2 instances running Ubuntu 22.04, and a single NAT Gateway. The ALB is deployed across two Public Subnets in different Availability Zones. The three backend services reside in a Private Subnet without public IPs. There is no Nginx or separate dedicated Ansible controller machine. `app01` manages itself via a `local` connection and manages the rest via SSH.

## Running from PowerShell

Create your own local keys before deployment (never commit them):

```powershell
New-Item -ItemType Directory -Force keys
ssh-keygen -t ed25519 -f keys/admin
ssh-keygen -t ed25519 -f keys/managed
```

Use an empty passphrase for this lab because the Terraform SSH provisioner reads the private key directly. Do not share private keys or state files. Before deployment, review the two `# ADMIN_IP` lines in `main.tf`; the published placeholder is `203.0.113.10/32`; replace it with your own public IP followed by `/32`. If it changes, update both lines. The AMI, IP addresses, and AZs are fixed for the `us-east-1` region.

From a terminal inside the project folder:

```powershell
terraform init
terraform plan
terraform apply
```

**After `terraform apply`, no manual SSH, SCP, or Ansible steps are required.** Terraform waits for the four servers and the network to be provisioned, connects to `app01`, waits for Ansible installation to complete, uploads `playbook.yml`, `inventory.ini`, `ansible.cfg`, and the private key for the managed servers, and runs the playbook directly from `app01`. The Ansible output streams in your Terraform terminal window. If Ansible fails, the `apply` command fails as well instead of declaring success.

This mechanism is defined at the end of `main.tf` under the `terraform_data.configure` resource, utilizing `file` provisioners for uploading and `remote-exec` for execution. This is an internal Terraform resource—**not a fifth server or a paid AWS service**. You do not need WSL, Python, or Ansible installed on your local machine.

Modifying the playbook, inventory, or `ansible.cfg` followed by `terraform apply` will automatically re-run Ansible without replacing the EC2 instances. If there are no changes, Terraform will not re-run it. To force a manual re-run from Terraform when needed:

```powershell
terraform apply '-replace=terraform_data.configure'
```

Installing Ansible and building Java on a `t3.micro` instance may take several minutes. Private keys are never uploaded to `user_data` or pushed to Git; only the managed key is transferred to `app01` with restricted permissions. The initial Terraform connection uses the default provisioner SSH behavior without pre-seeding the host fingerprint, which is configured for lab use.

## What Does the Playbook Do?

1. Generates random passwords on `app01` inside `~/vprofile/.secrets` with restricted permissions, and reuses the same values across subsequent runs.
2. Configures hostnames, essential packages, and a 2 GiB swap space for each small instance.
3. Sets up MariaDB, the application database user, and the `accounts` database. Imports the SQL schema only on the first run if the database is empty.
4. Configures Memcached to listen on private TCP only, and RabbitMQ using the application user instead of `guest`.
5. Installs Java 11 and Tomcat 9, and downloads a specific version of your source code.
6. **Ansible writes `src/main/resources/application.properties` completely**: database/cache/queue endpoints, ports, usernames, and correct passwords.
7. Runs Maven tests/builds, deploys `ROOT.war`, and verifies that `/login` returns an HTTP 200 status code.

All configurations are written directly inside `playbook.yml`, without external templates or roles. Re-running the playbook does not wipe the database, but it will rebuild the application. The secrets file is protected via Linux file permissions rather than Ansible Vault to minimize setup steps; do not expose it or commit it to Git. Keep a secure backup of it before replacing `app01`, because changing passwords will affect dependent services.

## Accessing the Application and Cleanup

From PowerShell:

```powershell
terraform output -raw website
```

Open the link after Ansible succeeds; it may take the ALB about a minute to mark the application target as healthy. Inbound HTTP traffic is restricted to your IP only, and HTTPS is disabled since there is no domain name or SSL certificate. This is a legacy application suited for testing, so do not use real user data. The Elasticsearch component found in the original source code is outside this four-server architecture, and its UI button will not function.

Tearing down the lab:

```powershell
terraform destroy
```

Destruction removes all servers, databases, and volumes; take a backup first if you need to retain data. Simply stopping the EC2 instances does not halt NAT and ALB billing or EBS storage charges. Your new account utilizes credits, but resources are not indefinitely free: NAT Gateways and ALBs alone cost approximately $49.28 per 730 hours at listed rates, prior to EC2, IPv4 public addresses, storage, and data transfer fees. Refer to [VPC Pricing](https://aws.amazon.com/vpc/pricing/) and [ALB Pricing](https://aws.amazon.com/elasticloadbalancing/pricing/).

<img width="1097" height="511" alt="image" src="https://github.com/user-attachments/assets/085a0e97-a3c4-470e-a76e-1c3abc4096b2" />

