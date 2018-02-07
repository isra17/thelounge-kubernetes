#!/bin/sh

# Create project:
export PROJECT=thelounge
export REGION=us-east1
export ZONE="$REGION-b"

gcloud projects create --name $PROJECT

# Create cluster:
gcloud container clusters create $PROJECT-cluster \
    --zone $ZONE -m n1-standard-1 --disk-size 50 \
    --num-nodes 1 --disable-addons 'HttpLoadBalancing,KubernetesDashboard'

# Import cluster certificates:
gcloud container clusters get-credentials $PROJECT-cluster --zone $ZONE
export CLUSTER=$(kubectl config get-clusters | grep $PROJECT-cluster)

# Create our data persistent disk:
gcloud compute disks create $PROJECT-data-pd --size 50 --zone $ZONE --type pd-standard
gcloud compute disks create bitlbee-data-pd --size 1 --zone $ZONE --type pd-standard

# Set up ingress

gcloud compute addresses create $PROJECT-cluster-ip --region $REGION --cluster $CLUSTER
export INGRESS_IP=$(gcloud compute addresses list | grep matrix-cluster-ip | awk '{print $3}')

# Assign to Compute Engine:
export LB_INSTANCE_NAME=$(kubectl describe nodes --cluster $CLUSTER | head -n1 | awk '{print $2}')
export LB_INSTANCE_NAT=$(gcloud compute instances describe $LB_INSTANCE_NAME | grep -A3 networkInterfaces: | tail -n1 | awk -F': ' '{print $2}')
gcloud compute instances delete-access-config $LB_INSTANCE_NAME \
  --access-config-name "$LB_INSTANCE_NAT"
gcloud compute instances add-access-config $LB_INSTANCE_NAME \
  --access-config-name "$LB_INSTANCE_NAT" --address $INGRESS_IP

# Assign role to the node:
kubectl label nodes $LB_INSTANCE_NAME role=load-balancer --cluster $CLUSTER

# Enable HTTP, HTTPS and 8448 on node:

gcloud compute instances add-tags $LB_INSTANCE_NAME --tags http-server,https-server

#Create the ingress controller:
kubectl --cluster $CLUSTER create -f nginx/nginx-ingress-controller.yaml

#Create the lego app for auto certificates renew:
kubectl --cluster $CLUSTER create -f nginx/lego.yaml

# Deploy thelounge
kubectl --cluster $CLUSTER create -f thelounge/

# Deploy thelounge
kubectl --cluster $CLUSTER create -f bitlbee/
