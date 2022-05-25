#!/usr/bin/env bash

# Copyright (c) Microsoft Corporation.
# Licensed under the MIT license.

PRJ_ROOT="$(cd `dirname "${BASH_SOURCE}"`/..; pwd)"
set -ex

ENVCODE=$1
PIPELINE_NAME=$2
DETECTION_MODEL_RUN_HOST_TYPE="${3:-batch}" # possible values: batch or aks

echo 'Retrieving resources from Azure ...'
RAW_STORAGE_ACCT=$(az storage account list --query "[?tags.store && tags.store == 'raw'].name" -o tsv -g $ENVCODE-data-rg)
SYNAPSE_STORAGE_ACCT=$(az storage account list --query "[?tags.store && tags.store == 'synapse'].name" -o tsv -g $ENVCODE-pipeline-rg)

if [[ "${DETECTION_MODEL_RUN_HOST_TYPE}" == "batch" ]];
then
    BATCH_STORAGE_ACCT=$(az storage account list --query "[?tags.store && tags.store == 'batch'].name" -o tsv -g $ENVCODE-orc-rg)
    BATCH_ACCT=$(az batch account list --query "[?tags.type && tags.type == 'batch'].name" -o tsv -g $ENVCODE-orc-rg)
    BATCH_ACCT_LOCATION=$(az batch account list --query "[?tags.type && tags.type == 'batch'].location" -o tsv -g $ENVCODE-orc-rg)
else
    AKS_ID=$(az aks list -g ${ENVCODE}-orc-rg --query "[?tags.type && tags.type == 'k8s'].id" -otsv)
    PERSISTENT_VOLUME_CLAIM="${ENVCODE}-vision-fileshare"
    AKS_MANAGEMENT_REST_URL="https://management.azure.com${AKS_ID}/runCommand?api-version=2022-02-01"
    BASE64ENCODEDZIPCONTENT_FUNCTIONAPP_HOST=$(az functionapp list -g ${ENVCODE}-orc-rg \
        --query "[?tags.type && tags.type == 'functionapp'].hostNames[0]" | jq -r '.[0]')
    BASE64ENCODEDZIPCONTENT_FUNCTIONAPP_URL="https://${BASE64ENCODEDZIPCONTENT_FUNCTIONAPP_HOST}"
fi

KEY_VAULT=$(az keyvault list --query "[?tags.usage && tags.usage == 'linkedService'].name" -o tsv -g $ENVCODE-pipeline-rg)
SYNAPSE_WORKSPACE=$(az synapse workspace list --query "[?tags.workspaceId && tags.workspaceId == 'default'].name" -o tsv -g $ENVCODE-pipeline-rg)
echo $SYNAPSE_WORKSPACE
SYNAPSE_WORKSPACE_RG=$(az synapse workspace list --query "[?tags.workspaceId && tags.workspaceId == 'default'].resourceGroup" -o tsv -g $ENVCODE-pipeline-rg)
echo $SYNAPSE_WORKSPACE_RG
SYNAPSE_POOL=$(az synapse spark pool list --workspace-name $SYNAPSE_WORKSPACE --resource-group $SYNAPSE_WORKSPACE_RG --query "[?tags.poolId && tags.poolId == 'default'].name" -o tsv -g $ENVCODE-pipeline-rg)
echo $SYNAPSE_POOL

echo 'Retrieved resource from Azure and ready to package'
if [[ "${DETECTION_MODEL_RUN_HOST_TYPE}" == "batch" ]];
then
    PACKAGING_SCRIPT="python3 ${PRJ_ROOT}/deploy/package.py --raw_storage_account_name $RAW_STORAGE_ACCT \
        --synapse_storage_account_name $SYNAPSE_STORAGE_ACCT \
        --detection_model_run_host_type batch \
        --batch_storage_account_name $BATCH_STORAGE_ACCT \
        --batch_account $BATCH_ACCT \
        --linked_key_vault $KEY_VAULT \
        --synapse_pool_name $SYNAPSE_POOL \
        --location $BATCH_ACCT_LOCATION \
        --pipeline_name $PIPELINE_NAME"
else
    PACKAGING_SCRIPT="python3 ${PRJ_ROOT}/deploy/package.py --raw_storage_account_name $RAW_STORAGE_ACCT \
        --synapse_storage_account_name $SYNAPSE_STORAGE_ACCT \
        --detection_model_run_host_type aks \
        --persistent_volume_claim $PERSISTENT_VOLUME_CLAIM \
        --aks_management_rest_url $AKS_MANAGEMENT_REST_URL \
        --base64encodedzipcontent_functionapp_url $BASE64ENCODEDZIPCONTENT_FUNCTIONAPP_URL \
        --linked_key_vault $KEY_VAULT \
        --synapse_pool_name $SYNAPSE_POOL \
        --pipeline_name $PIPELINE_NAME"
fi

echo $PACKAGING_SCRIPT
set -x

echo 'Starting packaging script ...'
$PACKAGING_SCRIPT

echo 'Packaging script completed'