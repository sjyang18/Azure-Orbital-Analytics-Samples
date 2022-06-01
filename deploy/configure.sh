#!/usr/bin/env bash

# Copyright (c) Microsoft Corporation.
# Licensed under the MIT license.

PRJ_ROOT="$(cd `dirname "${BASH_SOURCE}"`/..; pwd)"
ENVCODE=$1
DETECTION_MODEL_RUN_HOST_TYPE="${2:-batch}" # possible values: batch or aks
echo "DETECTION_MODEL_RUN_HOST_TYPE: "  $DETECTION_MODEL_RUN_HOST_TYPE
echo "configuration started ..."

set -x

# get synapse workspace and pool
SYNAPSE_WORKSPACE=$(az synapse workspace list --query "[?tags.workspaceId && tags.workspaceId == 'default'].name" -o tsv -g $1-pipeline-rg)
echo $SYNAPSE_WORKSPACE
SYNAPSE_WORKSPACE_RG=$(az synapse workspace list --query "[?tags.workspaceId && tags.workspaceId == 'default'].resourceGroup" -o tsv -g $1-pipeline-rg)
echo $SYNAPSE_WORKSPACE_RG
SYNAPSE_POOL=$(az synapse spark pool list --workspace-name ${SYNAPSE_WORKSPACE} --resource-group ${SYNAPSE_WORKSPACE_RG} --query "[?tags.poolId && tags.poolId == 'default'].name" -o tsv -g $1-pipeline-rg)
echo $SYNAPSE_POOL

if [[ -n $SYNAPSE_WORKSPACE ]] && [[ -n $SYNAPSE_WORKSPACE_RG ]] && [[ -n $SYNAPSE_POOL ]]
then
    # upload synapse pool 
    az synapse spark pool update --name ${SYNAPSE_POOL} --workspace-name ${SYNAPSE_WORKSPACE} --resource-group ${ENVCODE}-pipeline-rg --library-requirements "${PRJ_ROOT}/deploy/environment.yml"
fi

if [[ "${DETECTION_MODEL_RUN_HOST_TYPE}" == "batch" ]];
then
    # get batch account
    BATCH_ACCT=$(az batch account list --query "[?tags.type && tags.type == 'batch'].name" -o tsv -g ${ENVCODE}-orc-rg)
    echo $BATCH_ACCT

    BATCH_ACCT_KEY=$(az batch account keys list --name ${BATCH_ACCT} --resource-group ${ENVCODE}-orc-rg | jq ".primary")

    if [[ -n $BATCH_ACCT ]]
    then
        az batch account login --name ${BATCH_ACCT} --resource-group ${ENVCODE}-orc-rg
        # create batch job for custom vision model
        az batch job create --id 'custom-vision-model-job' --pool-id 'data-cpu-pool' --account-name ${BATCH_ACCT} --account-key ${BATCH_ACCT_KEY}
    fi
else # aks model run hosts
    DATA_RESOURCE_GROUP="${ENVCODE}-data-rg"
    AKS_NAMESPACE=vision
    PV_SUFFIX=fileshare
    VISION_FILE_SHARE_NAME=volume-a
    PV_NAME="${ENVCODE}-${AKS_NAMESPACE}-${PV_SUFFIX}"

    RAW_STORAGE_ACCT=$(az storage account list --query "[?tags.store && tags.store == 'raw'].name" -o tsv -g $DATA_RESOURCE_GROUP)
    RAW_STORAGE_KEY=$(az storage account keys list --resource-group $DATA_RESOURCE_GROUP --account-name $RAW_STORAGE_ACCT --query "[0].value" -o tsv)

    AKS_CLUSTER_NAME=$(az aks list -g ${ENVCODE}-orc-rg --query "[?tags.type && tags.type == 'k8s'].name" -otsv)
    az aks get-credentials --resource-group ${ENVCODE}-orc-rg --name ${AKS_CLUSTER_NAME} --context ${AKS_CLUSTER_NAME} --overwrite-existing
    kubectl config set-context ${AKS_CLUSTER_NAME}

    cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Namespace
metadata:
  name: $AKS_NAMESPACE
EOF

    cat <<EOF | kubectl -n $AKS_NAMESPACE apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: azure-secret
  namespace: $AKS_NAMESPACE
type: Opaque
stringData:
  azurestorageaccountname: ${RAW_STORAGE_ACCT}
  azurestorageaccountkey: ${RAW_STORAGE_KEY}
EOF

    cat <<EOF | kubectl -n $AKS_NAMESPACE apply -f -
apiVersion: v1
kind: PersistentVolume
metadata:
  name: ${PV_NAME}
spec:
  capacity:
    storage: 5Gi
  accessModes:
    - ReadWriteMany
  persistentVolumeReclaimPolicy: Retain
  storageClassName: azurefile-csi
  csi:
    driver: file.csi.azure.com
    readOnly: false
    volumeHandle: ${PV_NAME}
    volumeAttributes:
      resourceGroup: ${DATA_RESOURCE_GROUP}
      shareName: ${VISION_FILE_SHARE_NAME}
    nodeStageSecretRef:
      name: azure-secret
      namespace: ${AKS_NAMESPACE}
  mountOptions:
    - dir_mode=0777
    - file_mode=0777
    - uid=0
    - gid=0
    - mfsymlinks
    - cache=strict
    - nosharesock
    - nobrl
EOF


    cat << EOF | kubectl -n $AKS_NAMESPACE apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: ${PV_NAME}
spec:
  accessModes:
    - ReadWriteMany
  storageClassName: azurefile-csi
  volumeName: ${PV_NAME}
  resources:
    requests:
      storage: 5Gi
EOF

fi # end of either batch or aks related configuration

SYNAPSE_STORAGE_ACCT=$(az storage account list --query "[?tags.store && tags.store == 'synapse'].name" -o tsv -g $1-pipeline-rg)
echo $SYNAPSE_STORAGE_ACCT

if [[ -n $SYNAPSE_STORAGE_ACCT ]]
then
    # create a container to upload the spark job python files
    az storage container create --name "spark-jobs" --account-name ${SYNAPSE_STORAGE_ACCT}
    # uploads the spark job python files
    az storage blob upload-batch --destination "spark-jobs" --account-name ${SYNAPSE_STORAGE_ACCT} --source "${PRJ_ROOT}/src/transforms/spark-jobs"
fi

set +x

echo "configuration completed!"
