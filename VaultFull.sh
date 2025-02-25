#!/bin/bash

# Exit script on any error
set -e

# Function to print messages
print_message() {
    echo -e "\n🔹 $1..."
}

print_message "Updating system packages"
sudo dnf update -y

print_message "Installing AWS CLI"
sudo dnf install -y awscli

print_message "Verifying AWS CLI installation"
awscli --version || aws --version || { echo "❌ AWS CLI installation failed"; exit 1; }

print_message "Ensuring full curl is installed"
sudo dnf swap curl-minimal curl -y

print_message "Installing required dependencies"
sudo dnf install -y yum-utils jq

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

print_message "Setting correct permissions for Vault config and storage"
sudo chown vault:vault /etc/vault/config.hcl /opt/vault
sudo chmod 640 /etc/vault/config.hcl
sudo chmod -R 750 /opt/vault

print_message "Creating systemd service for Vault"
cat <<EOF | sudo tee /etc/systemd/system/vault.service
[Unit]
Description=Vault Server
After=network-online.target
Wants=network-online.target

[Service]
# Run as vault user
ExecStart=/usr/bin/vault server -config=/etc/vault/config.hcl
Restart=always
User=vault

[Install]
WantedBy=multi-user.target
EOF

print_message "Reloading systemd and starting Vault"
sudo systemctl daemon-reload
sudo systemctl enable vault
sudo systemctl start vault

print_message "Waiting for Vault to start..."
for i in {1..10}; do
    if curl -s "http://127.0.0.1:8200/v1/sys/health" | grep -q "initialized"; then
        break
    fi
    sleep 2
done
if ! systemctl is-active --quiet vault; then
    echo "❌ Vault did not start properly. Check logs: journalctl -u vault --no-pager --lines=50"
    exit 1
fi

print_message "Vault is running successfully!"

print_message "Setting Vault environment variable"
export VAULT_ADDR="http://127.0.0.1:8200"

print_message "Checking Vault initialization status"
VAULT_STATUS=$(vault status -format=json 2>/dev/null || echo "{}")
if echo "$VAULT_STATUS" | jq -r '.initialized' | grep -q "true"; then
    print_message "Vault is already initialized"
    if echo "$VAULT_STATUS" | jq -r '.sealed' | grep -q "false"; then
        print_message "Vault is unsealed. Checking existing token..."
        if [ -f ~/.vault-token ] && vault token lookup >/dev/null 2>&1; then
            ROOT_TOKEN=$(cat ~/.vault-token)
            echo "✅ Using existing root token from token helper: $ROOT_TOKEN"
        else
            read -sp "Enter existing Root Token (or press Enter to reinitialize): " ROOT_TOKEN
            echo ""
            if [ -n "$ROOT_TOKEN" ]; then
                export VAULT_TOKEN="$ROOT_TOKEN"
                vault token lookup || { echo "❌ Invalid token provided"; exit 1; }
                echo "✅ Successfully logged in with provided root token: $ROOT_TOKEN"
            else
                print_message "Reinitializing Vault..."
                INIT_OUTPUT=$(vault operator init -format=json)
                echo "$INIT_OUTPUT" | jq -r '.unseal_keys_b64[]' > ~/vault_unseal_keys.txt
                ROOT_TOKEN=$(echo "$INIT_OUTPUT" | jq -r '.root_token')
                echo "$ROOT_TOKEN" > ~/vault_root_token.txt
                print_message "Unsealing Vault with 3 unseal keys"
                vault operator unseal $(head -n 1 ~/vault_unseal_keys.txt)
                vault operator unseal $(head -n 2 ~/vault_unseal_keys.txt | tail -n 1)
                vault operator unseal $(head -n 3 ~/vault_unseal_keys.txt | tail -n 1)
                export VAULT_TOKEN="$ROOT_TOKEN"
                vault token lookup || { echo "❌ Failed to login with new root token"; exit 1; }
                echo "✅ Successfully logged in with new root token: $ROOT_TOKEN"
            fi
        fi
    else
        print_message "Vault is sealed. Unsealing required..."
        for i in {1..3}; do
            read -sp "Enter Unseal Key $i: " UNSEAL_KEY
            echo ""
            vault operator unseal "$UNSEAL_KEY" || { echo "❌ Unseal failed"; exit 1; }
        done
        read -sp "Enter Root Token: " ROOT_TOKEN
        echo ""
        export VAULT_TOKEN="$ROOT_TOKEN"
        vault token lookup || { echo "❌ Failed to login with root token"; exit 1; }
    fi
else
    print_message "Initializing Vault..."
    INIT_OUTPUT=$(vault operator init -format=json)
    echo "$INIT_OUTPUT" | jq -r '.unseal_keys_b64[]' > ~/vault_unseal_keys.txt
    ROOT_TOKEN=$(echo "$INIT_OUTPUT" | jq -r '.root_token')
    echo "$ROOT_TOKEN" > ~/vault_root_token.txt
    print_message "Unsealing Vault with 3 unseal keys"
    vault operator unseal $(head -n 1 ~/vault_unseal_keys.txt)
    vault operator unseal $(head -n 2 ~/vault_unseal_keys.txt | tail -n 1)
    vault operator unseal $(head -n 3 ~/vault_unseal_keys.txt | tail -n 1)
    export VAULT_TOKEN="$ROOT_TOKEN"
    vault token lookup || { echo "❌ Failed to login with root token"; exit 1; }
    echo "✅ Successfully logged in with root token: $ROOT_TOKEN"
fi

# AWS Secrets Engine Configuration
print_message "Enabling AWS Secrets Engine"
vault secrets enable -path=aws aws

print_message "Prompting for AWS Credentials"
read -p "Enter AWS Access Key: " AWS_ACCESS_KEY
read -sp "Enter AWS Secret Key: " AWS_SECRET_KEY
echo ""
read -p "Enter AWS Account Number: " AWS_ACCOUNT_NUMBER

print_message "Configuring AWS Secrets Engine with root credentials"
vault write aws/config/root \
    access_key="$AWS_ACCESS_KEY" \
    secret_key="$AWS_SECRET_KEY" \
    region="us-east-1"

print_message "Configuring AWS role for STS credentials"
vault write aws/roles/jenkins-role \
    credential_type=assumed_role \
    role_arns="arn:aws:iam::$AWS_ACCOUNT_NUMBER:role/VaultAccessRole"

print_message "Testing AWS STS credential generation"
vault read aws/creds/jenkins-role || { echo "❌ Failed to generate STS credentials. Check AWS credentials and VaultAccessRole trust policy."; exit 1; }
echo "✅ Successfully generated STS credentials for jenkins-role"

# Additional Vault Configuration for Jenkins
print_message "Enabling KV v2 Secrets Engine"
vault secrets enable -path=secret kv-v2

print_message "Creating Jenkins policy"
vault policy write jenkins-policy -<<EOF
path "aws/creds/jenkins-role" {
    capabilities = ["read"]
}
path "secret/data/*" {
    capabilities = ["create", "update", "read"]
}
path "secret/metadata/*" {
    capabilities = ["list"]
}
EOF

print_message "Setting up AppRole for Jenkins"
vault auth enable approle
vault write auth/approle/role/jenkins-role \
    token_policies="default,jenkins-policy" \
    token_ttl=1h \
    token_max_ttl=4h

print_message "Retrieving AppRole credentials"
ROLE_ID=$(vault read -field=role_id auth/approle/role/jenkins-role/role-id)
SECRET_ID=$(vault write -f -field=secret_id auth/approle/role/jenkins-role/secret-id)
echo "✅ Jenkins AppRole Role ID: $ROLE_ID"
echo "✅ Jenkins AppRole Secret ID: $SECRET_ID"

print_message "Retrieving Public IP"
PUBLIC_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)

print_message "Vault setup is complete!"
echo "✅ Access Vault UI at: http://$PUBLIC_IP:8200"
echo "✅ Use ROLE_ID: $ROLE_ID and SECRET_ID: $SECRET_ID in Jenkins Vault Plugin"

print_message "Securely removing unseal keys and root token file"
shred -u ~/vault_unseal_keys.txt ~/vault_root_token.txt
