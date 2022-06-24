# cidr-filtering-cni

This CNI plugin isolates pods from external endpoints. By default, all ingress and egress traffic is denied.
Users may create special ConfigMaps in the pod namespace to indicate allowed ingress or egress connections.
This can be done in both directions - ingress and egress - for network layers L3 and L4.
The supported L4 protocols are UDP and TCP.

## Requirements

- jq
- nftables
- sha1sum

## Usage

When using the cidr-filtering-cni plugin, all ingress and egress traffic is dropped by default. To enable cidr-filtering-cni plugin, include it in the
NetworkAttachmentDefinition. See the following example:

```yaml
---
apiVersion: "k8s.cni.cncf.io/v1"
kind: NetworkAttachmentDefinition
metadata:
  name: example-network
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
```

The `example-network` specifies two CNI plugins, the first cni in the above is a `cnv-bridge`, connecting pods to linux-bridge `br1`, and the second
is the `cidr-filtering-cni`, that handles configuration of nftables rules on the pod.

By default, all ingress and egress traffic is dropped.
To allow specific ingress and egress CIDR blocks/ports, create ConfigMaps(s) referencing a NetworkAttachmentDefinition spec.config name in the ConfigMap's label.
Each ConfigMap additionally needs to have `cidr-filtering-cni` label to be enabled for the cidr-filtering-cni plugin.

The following manifest is an example of a minimal ConfigMap, that doesn't yet allow any traffic. It's given as an example, since denying all traffic is done by default, it's
not needed to be explicitly created.

```yaml
kind: ConfigMap
apiVersion: v1
metadata:
  name: deny-all
  labels:
    cidr-filtering-cni: ""
    br1-with-cidr-filtering: ""
data:
  config.json: |
    {
      "ingress": {},
      "egress": {}
    }
```

Notice the labels of the ConfigMap.
The first label, `cidr-filtering-cni` ensures that the ConfigMap configuration is collected by the plugin, as
the plugin only lists configMaps with this label.
The second label, `br1-with-cidr-filtering` refers to the NetworkAttachmentDefinition spec name, in the CNI configuration JSON.


> **_NOTE:_**  A ConfigMap may refer to many NetworkAttachmentDefinition specs. The order in which ConfigMaps are process is not defined.


To allow a pod to communicate to external entities, let's create the following configMap, that allows pod to reach all ports
on a local network:

```yaml
---
kind: ConfigMap
apiVersion: v1
metadata:
  name: egress-local-network
  namespace: default
  labels:
    cidr-filtering-cni: ""
    br1-with-cidr-filtering: ""
data:
  config.json: |
    {
      "egress": {
        "subnets": [
          {
            "subnet": {
              "cidr": "192.168.0.0/16",
              "except": [
                "192.168.150.0/24",
                "192.168.151.151"
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
            "protocol": "tcp",
            "port": "8080"
          }
        ]
      }
    }
```

The `egress.subnets` attribute allows pod to reach to any IP address in subnet `192.168.0.0/16`, except for subnet `192.168.150.0/24` and `192.168.151.151`.
The `egress.ports` attribute allows pod to reach ports 80, and 8080 over TCP protocol.

To allow any webserver responses to be allowed to reach the pod, create the following ConfigMap:
```yaml
kind: ConfigMap
apiVersion: v1
metadata:
  name: ingress-local-network
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
              "cidr": "192.168.0.0/16"
            }
          }
        ],
        "ports": []
      }
    }
```

The `ingress.subnets` attribute allows traffic from any IP address of subnet `192.168.0.0/16`, to reach the pod.
The `ingress.ports` attribute all ports (on both, TCP and UDP protocols) to be reachable on the pod.

When using a secondary network where clients obtain IP addresses from a DHCP server, users must allow egress to  the `255.255.255.255` IP address, thus allowing the `DHCP Discover` message to be sent.

```yaml
kind: ConfigMap
apiVersion: v1
metadata:
  name: local-network-dhcp
  namespace: default
  labels:
    cidr-filtering-cni: ""
    br1-with-cidr-filtering: ""
data:
  config.json: |
    {
      "egress": {
        "subnets": [
          {
            "subnet": {
              "cidr": "255.255.255.255/32",
              "except": []
            }
          }
        ],
        "ports": [
          {
            "protocol": "udp",
            "port": "67"
          }
        ]
      },
      "ingress": {
        "ports": [
          {
            "protocol": "udp",
            "port": "68"
          }
        ]
      }
    }
```

## API Reference

- ingress:
  - provided CIDR subnets are matched against packet source address (packet sender)
  - ports match destination port of a packet
- egress:
  - provided CIDR subnets are matched against packet destination address (packet receiver)
  - ports match destination port of a packet
- subnet:
  - cidr - a particular CIDR (Ex. "192.168.1.1/24","2001:db9::/64") that is allowed
  - except - list of CIDRs or IP ranges for which traffic should be dropped
- port:
  - protocol - protocol name in string. Supported protocols are tcp, udp
  - port - destination port or port range in string

> **_NOTE:_**  Do not except IP addresses that are to be allowed in another configMap, as excepted IP addresses are dropped immediately.

