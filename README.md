# bridge-filtering

This CNI plugin allows the user to control traffic flow at the IP address or port level (OSI layer 3 or 4) for particular applications in the Kubernetes cluster, thus specifying how a pod is allowed to communicate with various network "entities".
The supported L4 protocols are UDP and TCP. All ICMP traffic is allowed by `bridge-filtering-cni`.

The pod interface **must** be a port of a bridge (for example a kubevirt virtual machine connected with bridge binding method). By default, all ingress and egress traffic is denied.

Users may create special `ConfigMaps` in the pod namespace to indicate allowed ingress or egress connections.

Since the nftable rules implementing traffic filtering are only applied when a pod is created, the CNI **cannot** update the provisioned rules if those are updated in any of the referenced `ConfigMap`.
If a referenced configuration is changed, **all the pods that use it must be re-created in order to have up-to-date configuration**.

> **_NOTE:_**  The CNI plugin doesn't currently support scenarios that involve IPAM assigning an IP on the pod interface. 

This project provides a subset of features that are otherwise available through [k8snetworkplumbingwg/multi-networkpolicy](https://github.com/k8snetworkplumbingwg/multi-networkpolicy). However, unlike Multi Network Policies, the bridge-filtering CNI is operating on netfilter's `bridge` table, which makes it suitable for KubeVirt.

## Requirements

- jq
- nftables
- sha1sum

## Installation

To install the CNI plugin, create the `manifests/daemonset.yaml` resource.

For OpenShift cluster, use `manifests/daemonset_openshift.yaml`.

## Limitations

The plugin is currently not using conntrack to allow response traffic. The user is expected to configure ingress/egress policies accordingly.
Policies applying to clients (in a client/server architecture) must remember to accept the return traffic for their requests.

Connection tracking for the `bridge` family was only released on [kernel 5.3](https://wiki.nftables.org/wiki-nftables/index.php/Bridge_filtering);
as such, this feature would be unavailable for any kernels older than that.

## Usage

When your Kubernetes workloads use the bridge-filtering plugin, all ingress and egress traffic is dropped by default. Allowed traffic must be explicitly specified in `ConfigMap`(s), that reference particular `NetworkAttachmentDefinition`.¨

### Making a pod subject to bridge-filtering policies

Enable bridge-filtering for pod by adding specifying it in `NetworkAttachmentDefinition`.

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

The `example-network` specifies two CNI plugins, the first cni is a `cnv-bridge`, connecting pods to linux-bridge `br1`, and the second
is the `bridge-filtering` plugin, that creates filtering rules on the pod.
Once a pod is subject to these policies, all ingress and egress traffic is dropped.

### Allowing traffic to pass 

To allow specific ingress and egress datagrams, create `ConfigMap`(s) that reference a `NetworkAttachmentDefinition` spec.config name in the `ConfigMap`'s label.
Each `ConfigMap` additionally needs to have the `bridge-filtering` label to be enable the bridge-filtering plugin (this is to ensure the plugin only processes `ConfigMaps` that are intended for it).

The following manifest is an example of a minimal `ConfigMap`, that doesn't yet allow any traffic. This configuration is redundant, since denying all traffic is done by default.

```yaml
kind: ConfigMap
apiVersion: v1
metadata:
  name: deny-all
  labels:
    bridge-filtering: ""
    br1-with-cidr-filtering: ""
data:
  config: |
    {
      "ingress": {},
      "egress": {}
    }
```


Notice the labels of the ConfigMap:
1. `bridge-filtering` label ensures that the `ConfigMap` configuration is collected by the CNI plugin, as the plugin only lists `ConfigMaps` with this label.
2. The second label, `br1-with-cidr-filtering` refers to the `NetworkAttachmentDefinition` spec name, in the CNI configuration JSON.


> **_NOTE:_**  A ConfigMap may refer to many NetworkAttachmentDefinition specs. The order in which ConfigMaps are process is not defined.

To allow a pod to communicate to external entities, create the following `ConfigMap`:
```yaml
---
kind: ConfigMap
apiVersion: v1
metadata:
  name: egress-local-network
  namespace: default
  labels:
    bridge-filtering: ""
    br1-with-bridge-filtering: ""
data:
  config: |
    {
      "egress": {
        "subnets": [
          {
            "cidr": "192.168.0.0/16",
            "except": [
              "192.168.150.0/24",
              "192.168.151.151"
            ]
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

- the `egress.subnets` attribute allows pod to reach any IP address in subnet `192.168.0.0/16`, except for subnet `192.168.150.0/24` and `192.168.151.151`.
- the `egress.ports` attribute allows pod to reach ports 80, and 8080 over TCP protocol.


Now that we have allowed the client VM to send requests to a server, allow server responses to reach the pod. Create the following `ConfigMap`:
```yaml
kind: ConfigMap
apiVersion: v1
metadata:
  name: ingress-local-network
  labels:
    bridge-filtering: ""
    br1-with-bridge-filtering: ""
data:
  config: |
    {
      "ingress": {
        "subnets": [
          {
            "cidr": "192.168.0.0/16"
          }
        ],
        "ports": [
          {
            "protocol": "tcp"
          }
        ]
      }
    }
```

- the `ingress.subnets` attribute allows traffic from any IP address of subnet `192.168.0.0/16`, to reach the pod.
- the `ingress.ports` attribute contains an object that specifies only `protocol` to match `tcp`, that allows all TCP ports to be reachable on a pod.

> **_NOTE:_**  Similarly, if protocol is not important for filtering, it may be omitted. For example `{"port": "80-8080"}` allows ports `80-8080` for both, TCP and UDP. If neither port of protocol is specified in a `ingress.ports` array object, all ports on all protocols are allowed.

When using a network where clients obtain IP addresses from a DHCP server, users must allow egress to the `255.255.255.255` IP address and thus allowing the `DHCP Discover` message to be sent.

```yaml
kind: ConfigMap
apiVersion: v1
metadata:
  name: local-network-dhcp
  namespace: default
  labels:
    bridge-filtering: ""
    br1-with-bridge-filtering: ""
data:
  config: |
    {
      "egress": {
        "subnets": [
          {
            "cidr": "255.255.255.255/32"
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
        "subnets": [
          {
            "cidr": "192.168.66.0/24"
          }
        ],
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
- subnets: array of subnets to allow. If this field is not specified or it's empty, no subnets are allowed.
  - cidr
    - a particular CIDR (Ex. "192.168.1.1/24","2001:db9::/64") that is allowed
    - leave empty or unspecified to match all IPs.
  - except
    - list of CIDRs or IP ranges for which traffic should be dropped
- ports: array of ports to allow. If this field is not specified or it's empty, no ports are allowed.
  - protocol
    - protocol name in string. Supported protocols are tcp, udp
    - leave empty or unspecified to match all protocols
  - port
    - destination port or port range in string (Ex. "80", "80-8000", "80,81,82")
    - leave empty or unspecified to match all ports

> **_NOTE:_**  Do not except IP addresses that are to be allowed in a different `ConfigMap`, as packets with excepted IP addresses are dropped immediately.

