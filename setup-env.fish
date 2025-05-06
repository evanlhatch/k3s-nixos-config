#!/usr/bin/env fish

set ENV_FILE ".env"
set TEMPLATE_FILE ".env.template"

# Check if .env already exists
if test -f $ENV_FILE
    echo "The $ENV_FILE file already exists."
    echo "If you want to recreate it, please delete it first: rm $ENV_FILE"
    exit 0
end

# Check if template exists
if not test -f $TEMPLATE_FILE
    echo "Error: $TEMPLATE_FILE not found!"
    exit 1
end

# Copy template to .env
cp $TEMPLATE_FILE $ENV_FILE
echo "Created $ENV_FILE from template."

# Generate K3S_TOKEN if needed
set K3S_TOKEN (openssl rand -hex 32)
if test (string length $K3S_TOKEN) -eq 64
    sed -i "s/export K3S_TOKEN=\"generated-k3s-token-value\"/export K3S_TOKEN=\"$K3S_TOKEN\"/" $ENV_FILE
    echo "Generated new K3S_TOKEN and updated $ENV_FILE"
else
    echo "Warning: Failed to generate K3S_TOKEN. Please set it manually in $ENV_FILE"
end

echo ""
echo "Please edit $ENV_FILE to fill in your secrets:"
echo "nano $ENV_FILE"
echo ""
echo "After editing, allow direnv to load the environment:"
echo "direnv allow ."