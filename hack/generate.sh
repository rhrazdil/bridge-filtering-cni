#!/bin/bash


sed "s/SCRIPT_PLACEHOLDER/$(cat cidr-filtering-cni | base64 -w 0)/" ./template/daemonset.yaml > ./manifests/daemonset.yaml

