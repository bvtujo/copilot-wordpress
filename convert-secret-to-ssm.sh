#!/bin/bash
set -eo pipefail
# Check environment
[ -z "$COPILOT_APP" ] && echo "COPILOT_APP must be set in the environment" && exit 1
[ -z "$COPILOT_ENV" ] && echo "COPILOT_ENV must be set in the environment" && exit 1
# Get secret ID based on user input from CF template
echo "This script will generate the following SSM parameters from a database secret:"
echo "  /rds/db-user      the username for the aurora cluster"
echo "  /rds/db-password  the password for the cluster"
echo "  /rds/db-endpoint  the endpoint (host:port) for the cluster"
echo "  /rds/db-name      the name of the primary table"

echo "Describing secrets and searching for $1"
secretID=$(aws secretsmanager list-secrets | jq -r '.SecretList[].Name' | grep $1)
[ -z $secretID ] && echo "Found no secrets with IDs including $1" && exit 1
echo "Found secret $secretID"

echo "Getting secret value"
secretvalue=$(aws secretsmanager get-secret-value --secret-id $secretID | jq -r .SecretString)

echo "Creating SSM parameters:"
echo "/rds/db-endpoint"
aws --output text ssm put-parameter --name /rds/db-endpoint --value $(echo $secretvalue | jq -r '. | "\(.host):\(.port)"') --type SecureString\
  --tags Key=copilot-environment,Value=${COPILOT_ENV} Key=copilot-application,Value=${COPILOT_APP} || echo "Parameter already exists"

echo "/rds/db-password"
aws --output text ssm put-parameter --name /rds/db-password --value $(echo $secretvalue | jq -r '.password') --type SecureString\
  --tags Key=copilot-environment,Value=${COPILOT_ENV} Key=copilot-application,Value=${COPILOT_APP} || echo "Parameter already exists"

echo "/rds/db-user"
aws --output text ssm put-parameter --name /rds/db-user --value $(echo $secretvalue | jq -r '.username') --type SecureString\
  --tags Key=copilot-environment,Value=${COPILOT_ENV} Key=copilot-application,Value=${COPILOT_APP} || echo "Parameter already exists"

echo "/rds/db-name"
aws --output text ssm put-parameter --name /rds/db-name --value $(echo $secretvalue | jq -r '.dbname') --type SecureString\
  --tags Key=copilot-environment,Value=${COPILOT_ENV} Key=copilot-application,Value=${COPILOT_APP} || echo "Parameter already exists"