# 🔐 Automated HashiCorp Vault Setup for AWS + Jenkins Integration

This Bash script automates the installation, initialization, and configuration of **HashiCorp Vault** on an Amazon Linux system. It also provisions the **AWS secrets engine** and configures **AppRole authentication** for Jenkins, enabling dynamic AWS credential issuance and secure secret management in CI/CD pipelines.

---

## 🧱 What This Script Does

### 🛠️ System Setup
- Updates system packages
- Installs AWS CLI, `jq`, Vault, and required tools
- Configures full `curl` (swaps out `curl-minimal`)
- Sets up Vault configuration and data directories
- Creates and starts Vault as a `systemd` service

### 🔐 Vault Initialization & Unsealing
- Checks if Vault is already initialized
- If not, initializes Vault and stores:
  - 3 unseal keys (`~/vault_unseal_keys.txt`)
  - Root token (`~/vault_root_token.txt`)
- If Vault is sealed, prompts user for unseal keys
- Verifies Vault is up and running

### ☁️ AWS Secrets Engine
- Enables the AWS secrets engine
- Configures it using provided AWS root credentials
- Adds an IAM role (`VaultAccessRole`) to allow STS credential generation for Jenkins

### 🔁 Jenkins Integration via AppRole
- Enables the KV v2 engine under `secret/`
- Creates a custom Vault policy for Jenkins (`jenkins-policy`)
- Sets up AppRole authentication with that policy
- Outputs `ROLE_ID` and `SECRET_ID` for Jenkins usage
- Shreds sensitive token/unseal key files after setup

---

## ⚙️ Prerequisites

- Amazon Linux 2 or Amazon Linux 2023
- An IAM role named `VaultAccessRole` in your AWS account, trusted by Vault
- HashiCorp Vault and AWS CLI binaries must be accessible from your EC2 or VM
- Script must be run as a user with `sudo` privileges

---

## 🚀 Usage

```bash
chmod +x setup-vault.sh
./setup-vault.sh
