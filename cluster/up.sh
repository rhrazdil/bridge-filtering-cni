#!/bin/bash
#
# Copyright 2018-2022 Red Hat, Inc.
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

set -ex

SCRIPTS_PATH="$(dirname "$(realpath "$0")")"
source ${SCRIPTS_PATH}/cluster.sh

cluster::install

$(cluster::path)/cluster-up/up.sh

echo 'Installing packages'
for node in $(./cluster/kubectl.sh get nodes --no-headers | awk '{print $1}'); do
    ./cluster/cli.sh ssh ${node} -- sudo dnf install -y jq
done

echo 'Install kubevirt'
export RELEASE=v0.53.1
./cluster/kubectl.sh apply -f "https://github.com/kubevirt/kubevirt/releases/download/${RELEASE}/kubevirt-operator.yaml"
./cluster/kubectl.sh apply -f "https://github.com/kubevirt/kubevirt/releases/download/${RELEASE}/kubevirt-cr.yaml"
./cluster/kubectl.sh -n kubevirt wait kv kubevirt --for condition=Available --timeout 5m

echo 'Install knmstate'
./cluster/kubectl.sh apply -f https://github.com/nmstate/kubernetes-nmstate/releases/download/v0.71.0/nmstate.io_nmstates.yaml
./cluster/kubectl.sh apply -f https://github.com/nmstate/kubernetes-nmstate/releases/download/v0.71.0/namespace.yaml
./cluster/kubectl.sh apply -f https://github.com/nmstate/kubernetes-nmstate/releases/download/v0.71.0/service_account.yaml
./cluster/kubectl.sh apply -f https://github.com/nmstate/kubernetes-nmstate/releases/download/v0.71.0/role.yaml
./cluster/kubectl.sh apply -f https://github.com/nmstate/kubernetes-nmstate/releases/download/v0.71.0/role_binding.yaml
./cluster/kubectl.sh apply -f https://github.com/nmstate/kubernetes-nmstate/releases/download/v0.71.0/operator.yaml
cat <<EOF | ./cluster/kubectl.sh create -f -
apiVersion: nmstate.io/v1
kind: NMState
metadata:
  name: nmstate
EOF
./cluster/kubectl.sh -n nmstate wait deployment nmstate-operator --for condition=Available --timeout 5m
