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
```

You will be prompted to:
- Enter your **AWS Access Key** and **Secret Key**
- Provide your **AWS Account Number**
- If Vault is sealed, manually enter the 3 unseal keys

---

## 🧪 Post-Setup

- Vault UI is accessible at: `http://<public-ip>:8200`
- AppRole credentials for Jenkins are printed:
  - `ROLE_ID`
  - `SECRET_ID`
- These can be configured in the **Jenkins Vault Plugin**

You can test credential issuance manually:
```bash
vault read aws/creds/jenkins-role
```

---

## 🛡️ Security Considerations

- Vault is run **without TLS** in this script — **use behind a reverse proxy or enable TLS in production**.
- Root token and unseal keys are stored temporarily and then **securely shredded**.
- Tokens are time-limited via TTL settings.
- AWS IAM role (`VaultAccessRole`) should have minimum required permissions.
- Only the Vault server should have access to AWS root credentials during setup.

---

## 📥 Output Files (Temporary)

| File | Description |
|------|-------------|
| `~/vault_unseal_keys.txt` | Contains 3 base64 unseal keys (shredded after setup) |
| `~/vault_root_token.txt`  | Contains root token (shredded after setup) |

---

## 🧰 Tools Installed

- Vault (`dnf install -y vault`)
- AWS CLI (`awscli`)
- `jq`, `curl`, `yum-utils`

---

## 🧩 Services Used

| Service | Purpose |
|---------|---------|
| **Vault** | Secure secrets management |
| **AWS IAM** | Role-based access to generate STS credentials |
| **Systemd** | Manages the Vault service |
| **Jenkins** | Integrates with Vault via AppRole to retrieve dynamic AWS credentials |

---

## 📃 License

MIT – free to use, extend, and customize for your secure infrastructure needs.

---

## 🙌 Acknowledgments

Created as part of a **secure DevOps pipeline** to enable dynamic secrets management and remove static AWS credentials from CI/CD pipelines.
