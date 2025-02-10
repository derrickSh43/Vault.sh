#!/bin/bash

# Exit script on any error
set -e

# Function to print messages
print_message() {
    echo -e "\n🔹 $1..."
}

print_message "Updating system packages"
sudo dnf update -y

print_message "Installing required dependencies"
sudo dnf install -y yum-utils

print_message "Adding HashiCorp repository"
sudo yum-config-manager --add-repo https://rpm.releases.hashicorp.com/AmazonLinux/hashicorp.repo

print_message "Installing Vault"
sudo dnf install -y vault

print_message "Creating Vault configuration directories"
sudo mkdir -p /etc/vault /opt/vault/data

print_message "Setting up Vault configuration"
cat <<EOF | sudo tee /etc/vault/config.hcl
storage "file" {
  path = "/opt/vault/data"
}

listener "tcp" {
  address     = "0.0.0.0:8200"
  tls_disable = "true"
}

disable_mlock = true
ui = true
EOF

print_message "Setting correct permissions for Vault storage"
sudo chown -R vault:vault /opt/vault
sudo chmod -R 750 /opt/vault

print_message "Creating systemd service for Vault"
cat <<EOF | sudo tee /etc/systemd/system/vault.service
[Unit]
Description=Vault Server
After=network-online.target
Wants=network-online.target

[Service]
ExecStart=/usr/bin/vault server -config=/etc/vault/config.hcl
Restart=always
User=root

[Install]
WantedBy=multi-user.target
EOF

print_message "Reloading systemd and starting Vault"
sudo systemctl daemon-reload
sudo systemctl enable vault
sudo systemctl start vault

# Wait for Vault to be fully up before proceeding
print_message "Waiting for Vault to start..."
sleep 5

# Check if Vault is running
if ! systemctl is-active --quiet vault; then
    echo "❌ Vault did not start properly. Please check the logs using: journalctl -u vault --no-pager --lines=50"
    exit 1
fi

print_message "Vault is running successfully!"

print_message "Setting Vault environment variable"
export VAULT_ADDR="http://127.0.0.1:8200"

print_message "Initializing Vault..."
INIT_OUTPUT=$(vault operator init 2>/dev/null || { echo "❌ Vault initialization failed. Ensure Vault is running."; exit 1; })
echo "$INIT_OUTPUT" | grep "Unseal Key" > ~/vault_unseal_keys.txt
echo "$INIT_OUTPUT" | grep "Initial Root Token" > ~/vault_root_token.txt

print_message "Unseal keys and root token have been saved temporarily in ~/vault_unseal_keys.txt and ~/vault_root_token.txt"
print_message "You must manually unseal Vault using three of the keys"

# Prompt for unsealing manually
for i in {1..3}; do
    read -sp "Enter Unseal Key $i: " UNSEAL_KEY
    echo ""
    vault operator unseal "$UNSEAL_KEY"
done

print_message "Logging into Vault"
read -sp "Enter Root Token: " ROOT_TOKEN
echo ""
vault login "$ROOT_TOKEN"

print_message "Enabling AWS Secrets Engine"
vault secrets enable aws

# Prompt for AWS credentials securely
print_message "Enter AWS Credentials"
read -p "Enter AWS Access Key: " AWS_ACCESS_KEY
read -sp "Enter AWS Secret Key: " AWS_SECRET_KEY
echo ""

print_message "Configuring AWS Secrets Engine"
vault write aws/config/root \
    access_key="$AWS_ACCESS_KEY" \
    secret_key="$AWS_SECRET_KEY" \
    region="us-east-1"

print_message "Retrieving Public IP"
PUBLIC_IP=$(curl -s ifconfig.me)

print_message "Vault setup is complete!"
echo "✅ Access Vault UI at: http://$PUBLIC_IP:8200"

# Securely delete temporary stored keys
print_message "Securely removing unseal keys and root token file"
shred -u ~/vault_unseal_keys.txt ~/vault_root_token.txt
