#!/usr/bin/env bash

# Copyright (c) Microsoft Corporation.
# Licensed under the MIT license.

PRJ_ROOT="$(cd `dirname "${BASH_SOURCE}"`/..; pwd)"

ENV_CODE=${1:-${ENV_CODE}}
PIPELINE_NAME=${2:-${PIPELINE_NAME}}

BATCH_ACCOUNT_NAME=${3:-${BATCH_ACCOUNT_NAME}}
BATCH_ACCOUNT_RG_NAME=${4:-$BATCH_ACCOUNT_RG_NAME}
BATCH_STORAGE_ACCOUNT_NAME=${5:-${BATCH_STORAGE_ACCOUNT_NAME}}
KEY_VAULT_NAME=${6:-${KEY_VAULT_NAME}}

RAW_STORAGE_ACCOUNT_RG=${7:-${RAW_STORAGE_ACCOUNT_RG:-"${ENV_CODE}-data-rg"}}
RAW_STORAGE_ACCOUNT_NAME=${8:-${RAW_STORAGE_ACCOUNT_NAME}}

SYNAPSE_WORKSPACE_RG=${9:-${SYNAPSE_WORKSPACE_RG:-"${ENV_CODE}-pipeline-rg"}}
SYNAPSE_WORKSPACE_NAME=${10:-${SYNAPSE_WORKSPACE_NAME}}
SYNAPSE_STORAGE_ACCOUNT_NAME=${11:-${SYNAPSE_STORAGE_ACCOUNT_NAME}}
SYNAPSE_POOL=${12:-${SYNAPSE_POOL}}
DETECTION_MODEL_RUN_HOST_TYPE=${13:-${DETECTION_MODEL_RUN_HOST_TYPE:-"batch"}} # possible values: batch or aks

set -ex


if [[ -z "$BATCH_ACCOUNT_NAME" ]] && [[ -z "$BATCH_ACCOUNT_RG_NAME" ]]; then
    BATCH_ACCOUNT_RG_NAME="${ENV_CODE}-orc-rg"
fi
if [[ -z "$BATCH_ACCOUNT_NAME" ]]; then
    BATCH_ACCOUNT_NAME=$(az batch account list --query "[?tags.type && tags.type == 'batch'].name" -o tsv -g $BATCH_ACCOUNT_RG_NAME)
fi
if [[ -z "$BATCH_ACCOUNT_RG_NAME" ]]; then
    BATCH_ACCOUNT_ID=$(az batch account list --query "[?name == '${BATCH_ACCOUNT_NAME}'].id" -o tsv)
    BATCH_ACCOUNT_RG_NAME=$(az resource show --ids ${BATCH_ACCOUNT_ID} --query resourceGroup -o tsv)
fi

if [[ -z "$RAW_STORAGE_ACCOUNT_NAME" ]]; then
    RAW_STORAGE_ACCOUNT_NAME=$(az storage account list --query "[?tags.store && tags.store == 'raw'].name" -o tsv -g $RAW_STORAGE_ACCOUNT_RG)
fi
if [[ -z "$SYNAPSE_STORAGE_ACCOUNT_NAME" ]]; then
    SYNAPSE_STORAGE_ACCOUNT_NAME=$(az storage account list --query "[?tags.store && tags.store == 'synapse'].name" -o tsv -g $SYNAPSE_WORKSPACE_RG)
fi

if [[ "${DETECTION_MODEL_RUN_HOST_TYPE}" == "batch" ]];
then
    if [[ -z "$BATCH_ACCOUNT_NAME" ]] && [[ -z "$BATCH_ACCOUNT_RG_NAME" ]]; then
        BATCH_ACCOUNT_RG_NAME="${ENV_CODE}-orc-rg"
    fi
    if [[ -z "$BATCH_ACCOUNT_NAME" ]]; then
        BATCH_ACCOUNT_NAME=$(az batch account list --query "[?tags.type && tags.type == 'batch'].name" -o tsv -g $BATCH_ACCOUNT_RG_NAME)
    fi
    if [[ -z "$BATCH_ACCOUNT_RG_NAME" ]]; then
        BATCH_ACCOUNT_ID=$(az batch account list --query "[?name == '${BATCH_ACCOUNT_NAME}'].id" -o tsv)
        BATCH_ACCOUNT_RG_NAME=$(az resource show --ids ${BATCH_ACCOUNT_ID} --query resourceGroup -o tsv)
    fi
    if [[ -z "$BATCH_STORAGE_ACCOUNT_NAME" ]]; then
        BATCH_STORAGE_ACCOUNT_NAME=$(az storage account list --query "[?tags.store && tags.store == 'batch'].name" -o tsv -g $BATCH_ACCOUNT_RG_NAME)
        if [[ -z "$BATCH_STORAGE_ACCOUNT_NAME" ]]; then
            BATCH_STORAGE_ACCOUNT_NAME=$(az storage account list --resource-group $BATCH_ACCOUNT_RG_NAME --query [0].name -o tsv)
        fi
    fi
    if [[ -z "$BATCH_ACCOUNT_LOCATION" ]]; then
        BATCH_ACCOUNT_LOCATION=$(az batch account list --query "[?name == '${BATCH_ACCOUNT_NAME}'].location" -o tsv)
    fi
else
    AKS_ID=$(az aks list -g ${ENV_CODE}-orc-rg --query "[?tags.type && tags.type == 'k8s'].id" -otsv)
    while [[ ${AKS_ID} == '' ]];
    do
        sleep 60
        AKS_ID=$(az aks list -g ${ENV_CODE}-orc-rg --query "[?tags.type && tags.type == 'k8s'].id" -otsv)
    done

    PERSISTENT_VOLUME_CLAIM="${ENV_CODE}-vision-fileshare"
    AKS_MANAGEMENT_REST_URL="https://management.azure.com${AKS_ID}/runCommand?api-version=2022-02-01"
    BASE64ENCODEDZIPCONTENT_FUNCTIONAPP_HOST=$(az functionapp list -g ${ENV_CODE}-orc-rg \
        --query "[?tags.type && tags.type == 'functionapp'].hostNames[0]" | jq -r '.[0]')

    while [[ ${BASE64ENCODEDZIPCONTENT_FUNCTIONAPP_HOST} == '' ]];
    do
        sleep 60
        BASE64ENCODEDZIPCONTENT_FUNCTIONAPP_HOST=$(az functionapp list -g ${ENV_CODE}-orc-rg \
        --query "[?tags.type && tags.type == 'functionapp'].hostNames[0]" | jq -r '.[0]')
    done
    BASE64ENCODEDZIPCONTENT_FUNCTIONAPP_URL="https://${BASE64ENCODEDZIPCONTENT_FUNCTIONAPP_HOST}"
fi


if [[ -z "$KEY_VAULT_NAME" ]]; then
    KEY_VAULT_NAME=$(az keyvault list --query "[?tags.usage && tags.usage == 'linkedService'].name" -o tsv -g $SYNAPSE_WORKSPACE_RG)
fi
if [[ -z "$SYNAPSE_WORKSPACE_NAME" ]]; then
    SYNAPSE_WORKSPACE_NAME=$(az synapse workspace list --query "[?tags.workspaceId && tags.workspaceId == 'default'].name" -o tsv -g $SYNAPSE_WORKSPACE_RG)
    SYNAPSE_WORKSPACE_ID=$(az synapse workspace list --query "[?tags.workspaceId && tags.workspaceId == 'default'].id" -o tsv -g $SYNAPSE_WORKSPACE_RG)
else
    SYNAPSE_WORKSPACE_ID=$(az synapse workspace list --query "[?name == '${BATCH_ACCOUNT_NAME}'].id" -o tsv -g $SYNAPSE_WORKSPACE_RG)
fi
if [[ -z "$SYNAPSE_POOL" ]]; then
    SYNAPSE_POOL=$(az synapse spark pool list --workspace-name $SYNAPSE_WORKSPACE_NAME --resource-group $SYNAPSE_WORKSPACE_RG --query "[?tags.poolId && tags.poolId == 'default'].name" -o tsv)
fi

DB_SERVER_NAME=$(az postgres server list --resource-group $RAW_STORAGE_ACCOUNT_RG --query '[].fullyQualifiedDomainName' -o tsv)
echo $DB_SERVER_NAME
DB_NAME=$(az postgres server list --resource-group $RAW_STORAGE_ACCOUNT_RG --query '[].name' -o tsv)
echo $DB_NAME
DB_USERNAME=$(az postgres server list --resource-group $RAW_STORAGE_ACCOUNT_RG --query '[].administratorLogin' -o tsv)@$DB_NAME
echo $DB_USERNAME


echo 'Retrieved resource from Azure and ready to package'
if [[ "${DETECTION_MODEL_RUN_HOST_TYPE}" == "batch" ]];
then
    PACKAGING_SCRIPT="python3 ${PRJ_ROOT}/deploy/package.py --raw_storage_account_name $RAW_STORAGE_ACCOUNT_NAME \
        --synapse_storage_account_name $SYNAPSE_STORAGE_ACCOUNT_NAME \
        --detection_model_run_host_type batch \
        --batch_storage_account_name $BATCH_STORAGE_ACCOUNT_NAME \
        --batch_account $BATCH_ACCOUNT_NAME \
        --linked_key_vault $KEY_VAULT_NAME \
        --synapse_pool_name $SYNAPSE_POOL \
        --location $BATCH_ACCOUNT_LOCATION \
        --pipeline_name $PIPELINE_NAME \
        --synapse_workspace $SYNAPSE_WORKSPACE_NAME \
        --synapse_workspace_id $SYNAPSE_WORKSPACE_ID \
        --pg_db_username $DB_USERNAME \
        --pg_db_server_name $DB_SERVER_NAME"
else
    PACKAGING_SCRIPT="python3 ${PRJ_ROOT}/deploy/package.py --raw_storage_account_name $RAW_STORAGE_ACCOUNT_NAME \
        --synapse_storage_account_name $SYNAPSE_STORAGE_ACCOUNT_NAME \
        --detection_model_run_host_type aks \
        --persistent_volume_claim $PERSISTENT_VOLUME_CLAIM \
        --aks_management_rest_url $AKS_MANAGEMENT_REST_URL \
        --base64encodedzipcontent_functionapp_url $BASE64ENCODEDZIPCONTENT_FUNCTIONAPP_URL \
        --linked_key_vault $KEY_VAULT_NAME \
        --synapse_pool_name $SYNAPSE_POOL \
        --pipeline_name $PIPELINE_NAME \
        --synapse_workspace $SYNAPSE_WORKSPACE_NAME \
        --synapse_workspace_id $SYNAPSE_WORKSPACE_ID \
        --pg_db_username $DB_USERNAME \
        --pg_db_server_name $DB_SERVER_NAME"
fi

echo $PACKAGING_SCRIPT
echo 'Starting packaging script ...'
$PACKAGING_SCRIPT
echo 'Packaging script completed'