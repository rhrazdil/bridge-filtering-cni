# bridge-filtering

This CNI plugin allows the user to control traffic flow at the IP address or port level (OSI layer 3 or 4) for particular applications in the Kubernetes cluster, thus specifying how a pod is allowed to communicate with various network "entities". The pod interface must be a port of a bridge (for example a kubevirt virtual machine connected with bridge binding method). By default, all ingress and egress traffic is denied.
Users may create special ConfigMaps in the pod namespace to indicate allowed ingress or egress connections.
This can be done for network layers L3 and L4. The supported L4 protocols are UDP and TCP.

Since the nftable rules implementing traffic filtering are created when a pod is being created, the CNI cannot update the provisioned rules if those are updated in the `ConfigMaps`.
If a configuration in a `ConfigMap` is changed, all the pods that use it need to be re-created, in order to have up-to-date configuration.

> **_NOTE:_**  The CNI plugin doesn't currently support scenarios that involve IPAM assigning an IP on the pod interface. 

## Requirements

- jq
- nftables
- sha1sum

## Installation

To install the CNI plugin, create the `manifests/daemonset.yaml` resource.

## Usage

When using the bridge-filtering plugin, all ingress and egress traffic is dropped by default. To enable bridge-filtering plugin, include it in the
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
        "type": "bridge-filtering"
      }
    ]
  }'
```

The `example-network` specifies two CNI plugins, the first cni in the above is a `cnv-bridge`, connecting pods to linux-bridge `br1`, and the second
is the `bridge-filtering`, that handles configuration of nftables rules on the pod.

By default, all ingress and egress traffic is dropped.
To allow specific ingress and egress CIDR blocks/ports, create ConfigMaps(s) referencing a NetworkAttachmentDefinition spec.config name in the ConfigMap's label.
Each ConfigMap additionally needs to have `bridge-filtering` label to be enabled for the bridge-filtering plugin.

The following manifest is an example of a minimal `ConfigMap`, that doesn't yet allow any traffic. Since denying all traffic is done by default, it doesn't needed to exist.

```yaml
kind: ConfigMap
apiVersion: v1
metadata:
  name: deny-all
  labels:
    bridge-filtering: ""
    br1-with-cidr-filtering: ""
data:
  config.json: |
    {
      "ingress": {},
      "egress": {}
    }
```

Notice the labels of the ConfigMap.
The first label, `bridge-filtering` ensures that the `ConfigMap` configuration is collected by the CNI plugin, as
the plugin only lists `ConfigMaps` with this label.
The second label, `br1-with-cidr-filtering` refers to the `NetworkAttachmentDefinition` spec name, in the CNI configuration JSON.


> **_NOTE:_**  A ConfigMap may refer to many NetworkAttachmentDefinition specs. The order in which ConfigMaps are process is not defined.


To allow a pod to communicate to external entities, let's create the following `ConfigMap`, that allows pod to reach all ports
on a local network:

```yaml
---
kind: ConfigMap
apiVersion: v1
metadata:
  name: egress-local-network
  namespace: default
  labels:
    bridge-filtering: ""
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

The `egress.subnets` attribute allows pod to reach any IP address in subnet `192.168.0.0/16`, except for subnet `192.168.150.0/24` and `192.168.151.151`.
The `egress.ports` attribute allows pod to reach ports 80, and 8080 over TCP protocol.

To allow any webserver responses to be allowed to reach the pod, create the following ConfigMap:
```yaml
kind: ConfigMap
apiVersion: v1
metadata:
  name: ingress-local-network
  labels:
    bridge-filtering: ""
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
The `ingress.ports` attribute set to an empty array allows all ports (on both, TCP and UDP protocols) to be reachable on the pod.

When using a secondary network where clients obtain IP addresses from a DHCP server, users must allow egress to  the `255.255.255.255` IP address, thus allowing the `DHCP Discover` message to be sent.

```yaml
kind: ConfigMap
apiVersion: v1
metadata:
  name: local-network-dhcp
  namespace: default
  labels:
    bridge-filtering: ""
    br1-with-cidr-filtering: ""
data:
  config.json: |
    {
      "egress": {
        "subnets": [
          {
            "subnet": {
              "cidr": "255.255.255.255/32"
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
  - by default, all subnets are denied. Subnets configured in multiple `ConfigMaps` are combined using logical OR.
  - ports match destination port of a packet
- egress:
  - provided CIDR subnets are matched against packet destination address (packet receiver)
  - by default, all subnets are denied. Subnets configured in multiple `ConfigMaps` are combined using logical OR.
  - ports match destination port of a packet
- subnets: array of subnets to allow. If this field is not specified, no subnets are allowed. If empty array is specified, all subnets are allowed
  - cidr
    - a particular CIDR (Ex. "192.168.1.1/24","2001:db9::/64") that is allowed
  - except
    - list of CIDRs or IP ranges for which traffic should be dropped
- ports: array of ports to allow. If this field is not specified, no ports are allowed. If empty array is specified, all ports are allowed
  - protocol
    - protocol name in string. Supported protocols are tcp, udp
  - port
    - destination port or port range in string (Ex. "80", "80-8000", "80,81,82")

> **_NOTE:_**  Do not except IP addresses that are to be allowed in another ConfigMap, as excepted IP addresses are dropped immediately.

