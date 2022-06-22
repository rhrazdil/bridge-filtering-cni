# cidr-filtering-cni

This plugin allows user to define allow list for ingress and egress packet filtering for a Kubernetes pod.

## Requirements

- jq
- nftables
- sha1sum

## Usage

When using the cidr-filtering-cni plugin, all ingress and egress traffic is dropped by default.
To allow specific ingress and egress CIDR blocks/ports, create configMaps(s) referencing a NetworkAttachmentDefinition by having a label the NetworkAttachmentDefinition spec name.
Each configMap additionally needs to have "cidr-filtering-cni" label.

See the example below:

```yaml
---
apiVersion: "k8s.cni.cncf.io/v1"
kind: NetworkAttachmentDefinition
metadata:
  name: a-configmapped-network
spec:
  config: '{
    "cniVersion": "0.3.1",
    "name": "br1-with-cidr-filtering",
    "plugins": [
      {
        "type": "cnv-bridge",
        "bridge": "br1"
      },
      {
        "type": "cidr-filtering-cni"
      }
    ]
  }'
---
kind: ConfigMap
apiVersion: v1
metadata:
  name: local-network
  namespace: default
  labels:
    cidr-filtering-cni: ""
    br1-with-cidr-filtering: ""
data:
  config.json: |
    {
      "ingress": {
        "subnets": [
          {
            "subnet": {
              "cidr": "192.168.66.0/24",
              "except": [
                "192.168.66.105"
              ]
            }
          }
        ]
      },
      "egress": {
        "subnets": [
          {
            "subnet": {
              "cidr": "192.168.66.0/16",
              "except": [
                "192.168.1.0/24",
                "192.168.2.0/24"
              ]
            }
          }
        ]
      }
    }
```

Description of API fields:

- subnet:
  - cidr - network subnet in format: \<network_address\>/\<mask\>
  - except - list of IP addresses or IP ranges for which traffic should be dropped
- port:
  - protocol - protocol name in string, supported protocols are tcp, udp, icmp and icmpv6
  - port - port or port range in string
