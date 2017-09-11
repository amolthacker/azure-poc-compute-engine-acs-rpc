#!/bin/bash

###############################################################
# compute-engine-rpc deployment
###############################################################

#---------------------------------------------------
# 1. Login to Azure
#---------------------------------------------------
$ az login
#---------------------------------------------------

#---------------------------------------------------
# 2. Set Account to pre-created Subscription
#---------------------------------------------------
$ az account set --subscription <subscription-name/id>
#---------------------------------------------------

#---------------------------------------------------
# 3. Create Resource Group
#---------------------------------------------------
$ az group create -n <group-name> -l <location>
#---------------------------------------------------

#---------------------------------------------------
# 4. Create Service Principal for App in AD
#---------------------------------------------------
$ az ad sp create-for-rbac --role="Owner" --scopes="/subscriptions/<subscription-id>/resourceGroups/<group-name>" --name "tdsveritas"

{
  "appId": "app-id",
  "displayName": "tdsveritas",
  "name": "http://tdsveritas",
  "password": "app-pwd",
  "tenant": "tenant-id"
}
#---------------------------------------------------

#---------------------------------------------------
# 5. Copy appId and password to
#    servicePrincipalAppId & servicePrincipalAppKey
#    fields in azuredeploy.parameters.json
#---------------------------------------------------

#---------------------------------------------------
# 6. Deploy Resources using the ARM template
#---------------------------------------------------
$ git clone https://github.com/amolthacker/azure-poc-compute-engine-acs-rpc.git
$ cd compute-engine-rpc/provisioning
$ az group deployment create -g tds-veritas --template-file vtasazdeploy.json --parameters @vtasazdeploy.parameters.json
#---------------------------------------------------

#---------------------------------------------------
# 7. Setup AdminVM SSH Tunnel Config
#---------------------------------------------------
$ cd ../scripts
$ cp ssh-config ~/.ssh/config
./vtasadmin-tunnel.sh start
#---------------------------------------------------

###############################################################


###############################################################
# In Admin VM
###############################################################
ssh -i ~/.ssh/az vtasadmin@tds-veritas.northcentralus.cloudapp.azure.com

#---------------------------------------------------
# 8. Setup Jenkins CI
#---------------------------------------------------
# [a] Get Jenkins password from Admin VM fs
sudo cat /var/lib/jenkins/secrets/initialAdminPassword
exit

# [b] Log on to http://localhost:8080 and paste the above password

# [c] Install Recommended Plugins & Setup Admin User
#---------------------------------------------------

#---------------------------------------------------
# 9. Start Kubernetes Proxy on Admin VM
#---------------------------------------------------
nohup kubectl proxy 2>&1 < /dev/null &

#---------------------------------------------------
# OR [LOCAL on local machine]
# Remove Kubernetes tunnel settings from ~/.ssh/config and do following:
# Setup kubectl to access the Kubernetes cluster from local machine
#
# Install kubectl (https://kubernetes.io/docs/tasks/kubectl/install/)
brew install kubectl
#
# Download Kubernetes config to ~/.kube/config
az acs kubernetes get-credentials --ssh-key-file ~/.ssh/az --resource-group=tds-veritas-frtb-acs-kub --name=containerservice-tds-veritas-frtb-acs-kub
#
# Start Proxy
nohup kubectl proxy 2>&1 < /dev/null &
#---------------------------------------------------

#---------------------------------------------------
# 10. Install & Setup Go with dependencies
#---------------------------------------------------
# [a] Install Go
wget https://storage.googleapis.com/golang/go1.8.1.linux-amd64.tar.gz
sudo tar -C /usr/local -xzf go1.8.1.linux-amd64.tar.gz
#
# [b] Create Go Workspace dir
cd
mkdir go
#
# [c] Update ~/.profile with following
export PATH=$PATH:/usr/local/go/bin
export GOPATH=$HOME/go
#
# [d] Install dependencies
go get github.com/koding/kite
go get github.com/spf13/viper
go get bitbucket.org/amdatulabs/amdatu-kubernetes-go/client
#
#---------------------------------------------------

#---------------------------------------------------
# 11. Setup tds-veritas
#---------------------------------------------------
cd
mkdir -p tds-veritas/compute
mkdir -p tds-veritas/logs
cd tds-veritas/compute
git clone https://github.com/amolthacker/compute-engine
git clone https://github.com/amolthacker/compute-manager
#---------------------------------------------------

#---------------------------------------------------
# 12. Setup scripts
#---------------------------------------------------
# All scripts under scripts dir to
# /usr/local/bin without .sh and with chmod +x
#
# Download and copy websocketd to /usr/local/bin
#---------------------------------------------------

#---------------------------------------------------
# 13. Set Kubernetes HPA
#---------------------------------------------------
# Set resource requests for deployment valengine-prod
kubectl set resources deployment valengine-prod --requests=cpu=250m,memory=250Mi
#
# Define autoscale
kubectl autoscale deployment valengine-prod --min=2 --max=8 --cpu-percent=50
#
# Check status
kubectl describe hpa valengine-prod
kubectl get hpa
#---------------------------------------------------

#---------------------------------------------------
# 14. Start tds-veritas compute-manager
#---------------------------------------------------
cd ~/tds-veritas/compute/compute-manager
# Update prop agent_dns in config/env.toml to K8S LB External IP
./start-compute-manager.sh
#---------------------------------------------------

###############################################################


###############################################################
# In Client Machine [LOCAL]
###############################################################

#---------------------------------------------------
# 15. Access Dashbaords
#---------------------------------------------------
#
# Jenkins: 	       http://localhost:8080
# Spinnaker:       http://localhost:9000
# Kubernetes: 	   http://localhost:8001/ui
# Compute Manager: http://localhost:8090/index
#---------------------------------------------------

#---------------------------------------------------
# 16. Configure Spinnaker Pipeline
#---------------------------------------------------
# [a] Update the dev and prod Clusters (ServerGroup)
#     to use k8s Deployment[valengine-dev/prod]
#     See provisioning/spinnaker-cluster-k8s-rs-<dev/prod>.yaml
#     &&  provisioning/spinnaker-lb-k8s-svc-<dev/prod>.yaml
#
# [b] Create a new Pipeline and configure it using
#     the spinnaker-pipeline.json file
#
# [c] Ensure dev and prod Clusters (ServerGroup)
#     referenced by the pipeline use
#     k8s Deployment[valengine-dev/prod]
#     &
#     Have HPA setup with CPU/Mem Requests for
#     containers as described in Section 13
#
# [d] Ensure Pipeline's configured to resolve ACR
#     build tag and not use an exact tag
#
# [e] Delete the pre-created Pipeline
#
# [f] Do a dry-run through Start Manual Execution
#---------------------------------------------------

#---------------------------------------------------
# 17. Test
#---------------------------------------------------
# [a] Simulate compute load
./simulateValuationRequestsRemote.sh 1 500
./simulateValuationRequestsRemote.sh 2 500
#
# [b] Scale up/down compute
http://localhost:8090/api/scaleCompute/2
http://localhost:8090/api/scaleCompute/3
http://localhost:8090/api/scaleCompute/2
#
# [c] Show Deployment
http://localhost:8090/api/showDeployment
#
# [d] Submit Job
http://localhost:8090/api/submitJob/ParRate/10
#
# [e] Check in Code to trigger build and pipeline
#---------------------------------------------------
#
###############################################################
