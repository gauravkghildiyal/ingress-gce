#!/bin/bash
#
# Copyright 2018 The Kubernetes Authors.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# run.sh manages the settings required for running containerized in a
# Kubernetes cluster.
echo '--- BEGIN ---'

for ATTEMPT in $(seq 60); do
  PROJECT=$(curl -H'Metadata-Flavor:Google' metadata.google.internal/computeMetadata/v1/project/project-id 2>/dev/null)
  if [[ -n "$PROJECT" ]]; then
    break
  fi
  echo "Warning: could not get Compute project name from the metadata server (attempt ${ATTEMPT})"
  sleep 1
done

if [[ -z "$PROJECT" ]]; then
  echo "Error: could not get Compute project name from the metadata server"
  echo "RESULT: 2"
  echo '--- END ---'
  exit
fi

for ATTEMPT in $(seq 60); do
  ZONE_INFO=$(curl -H'Metadata-Flavor:Google' metadata.google.internal/computeMetadata/v1/instance/zone)
  if [[ -n "${ZONE_INFO}" ]]; then
    break
  fi
  echo "Error: could not get zone from the metadata server (attempt ${ATTEMPT})"
  sleep 1
done

if [[ -z "${ZONE_INFO}" ]]; then
  echo "Error: could not get zone info from the metadata server"
  echo "RESULT: 2"
  echo '--- END ---'
  exit
fi
echo "ZONE_INFO: ${ZONE_INFO}"

# Get Region information from zone info
ZONE=$(echo ${ZONE_INFO} | sed 's+projects/.*/zones/++')
REGION=$(echo ${ZONE} | sed 's/-[a-z]$//')

if [[ -z "${REGION}" ]]; then
  echo "Error: could not parse region from zone info"
  echo "Result: 2"
  exit
fi
echo "Using Region: ${REGION}"

# Get network information
for ATTEMPT in $(seq 60); do
  NETWORK_INFO=$(curl -H'Metadata-Flavor:Google' metadata.google.internal/computeMetadata/v1/instance/network-interfaces/0/network)
  if [[ -n "${NETWORK_INFO}" ]]; then
    break
  fi
  echo "Error: could not get network from the metadata server (attempt ${ATTEMPT})"
  sleep 1
done

NETWORK=$(echo ${NETWORK_INFO} | sed 's+projects/.*/networks/++')

if [[ -z "${NETWORK}" ]]; then
  echo "Error: could not parse network from network info"
  echo "Result: 2"
  exit
fi
echo "Using Network: ${NETWORK}"

# Get subnet  information
# We expect the custom metadata field 'cluster-subnet' on all VMs.
for ATTEMPT in $(seq 60); do
  SUBNET=$(curl -H'Metadata-Flavor:Google' metadata.google.internal/computeMetadata/v1/instance/attributes/cluster-subnet)
  if [[ -n "${SUBNET}" ]]; then
    break
  fi
  echo "Error: could not get subnet from the metadata server (attempt ${ATTEMPT})"
  sleep 1
done

if [[ -z "${SUBNET}" ]]; then
  echo "Error: could not get subnet"
  echo "Result: 2"
  exit
fi
echo "Using Subnet: ${SUBNET}"


echo
echo ==============================================================================
echo "PROJECT: ${PROJECT}"
CMD="/e2e-test -test.v -test.parallel=100 -run -project ${PROJECT} -region ${REGION} -network ${NETWORK} -logtostderr -inCluster -v=2"
echo "CMD: ${CMD}" $@
echo

echo ==============================================================================
echo E2E TEST
echo
${CMD} "$@" 2>&1
RESULT=$?
echo

if [[ "${DUMP_RESOURCES:-}" == "true" ]]; then
  GCLOUD=/google-cloud-sdk/bin/gcloud
  RESOURCES="forwarding-rules target-http-proxies target-https-proxies url-maps backend-services"
  for RES in ${RESOURCES}; do
    echo ==============================================================================
    echo "GCP RESOURCE: ${RES}"
    ${GCLOUD} compute ${RES} list --quiet --project ${PROJECT} --format yaml 2>&1
  done
fi

echo ==============================================================================
echo "RESULT: $RESULT"
echo '--- END ---'
