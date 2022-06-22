# cidr-filtering-cni

This plugin allows user to define allow list for ingress and egress packet filtering for a Kubernetes pod.

## Requirements

- jq
- nftables
- sha1sum

## Usage

By default, all ingress and egress traffic is dropped.
To allow specific ingress and egress CIDR blocks, create a NetworkAttachmentDefinition. See the following example:

```yaml
apiVersion: "k8s.cni.cncf.io/v1"
kind: NetworkAttachmentDefinition
metadata:
 name: a-policy-network
spec:
 config: '{
  "cniVersion": "0.3.1",
  "name": "nad-bridge-cidr",
  "plugins": [
    {
      "type": "cnv-bridge",
      "bridge": "br1"
    },
    {
      "type": "cidr-filtering-cni",
      "name": "p1",
      "ingress": {
        "blocks": [
          {
            "ipBlock": {
              "cidr": "192.168.66.0/24",
              "except": [
                "192.168.66.102",
                "192.168.66.103",
                "192.168.66.104",
                "192.168.66.105-192.168.66.107",
                "192.168.66.115/29"
              ]
            }
          }
        ],
        "ports": [
          {
            "protocol": "TCP",
            "port": "1-65535"
          },
          {
            "protocol": "udp",
            "port": "1-65535"
          }
        ]
      },
      "egress": {
        "blocks": [
          {
            "ipBlock": {
              "cidr": "192.168.66.0/24",
              "except": [
                "192.168.66.102"
              ]
            }
          }
        ],
        "ports": [
        {
          "protocol": "TCP",
          "port": "80"
        },
        {
          "protocol": "udp",
          "port": "1-4000"
        }
        ]
      }
    }
  ]
}'
```

Description of API fields:
- subnet:
  - cidr - network subnet in format: \<network_address\>/\<mask\>
  - except - list of IP addresses or IP ranges for which traffic should be dropped
- port:
  - protocol - protocol name in string, supported protocols are tcp, udp, icmp and icmpv6
  - port - port or port range in string
