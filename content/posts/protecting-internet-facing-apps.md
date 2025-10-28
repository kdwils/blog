+++
author = "Kyle Wilson"
title = "How I protect applications I expose to the public internet in Kubernetes with CrowdSec"
date = "2025-10-25"
description = ""
summary = ""
tags = [
    "homelab",
    "crowdsec",
    "envoy-gateway"
]
+++

## The pieces

In my last two blog posts I covered the envoy-proxy remediation component I wrote for crowdsec. Those topics were focused on the bouncer functionality, and I wanted to cover the pieces outside of the bouncer that when put together make the entire process work.

Basically, it all boils down to Cloudflared Tunnels, Cached IP decisions from crowdsec, and Envoy Gateway.

### Cloudflared Tunnels

Cloudflared Tunnels act as a "safer" ingress for services in my Kubernetes cluster. I won't go over the details of setting up Cloudflared in this post, but I've covered it in a [previous post](/posts/cloudflare-tunnel)

The tl;dr is we need to tell the tunnel to route traffic to Envoy Gateway. I am choosing to terminate TLS at the gateway and I need to make sure SNI will work for my wildcard certificate.

```yaml
  config.yaml: |
    tunnel: <my-tunnel>
    credentials-file: <my-cred-file>
    no-autoupdate: true
    protocol: http2
    metrics: 0.0.0.0:2000
    ingress:
      - hostname: blog.kyledev.co
        service: https://homelab-gateway.envoy-gateway-system.svc.cluster.local:443
        originRequest:
          originServerName: blog.kyledev.co
      - service: http_status:404
```

### CrowdSec Decisions

The [Local API](https://docs.crowdsec.net/docs/local_api/intro/) exposes endpoints for streaming live decision updates to remediation components. The decisions are tied to IP addresses, and instruct remediation components on what action to take (captcha, ban, etc) if the IP of an incoming request is tied to a decision.

The Envoy Proxy bouncer consumes from this stream on startup so it can apply decisions immediately.

### Envoy Gateway

This last piece acts as the ingress for all services in my cluster, including internal and exposed applications. Envoy gateway implements the Kubernetes gateway API, and communication to my Blog pod is made over HTTP, so we use a `HTTPRoute`.

The HTTPRoute for my blog looks like:
```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  labels:
    app: blog-prod
  name: blog-prod
  namespace: blog
spec:
  hostnames:
  - blog.kyledev.co
  parentRefs:
  - name: homelab
    namespace: envoy-gateway-system
  rules:
  - backendRefs:
    - name: blog-prod
      port: 80
```

Next, a `ReferenceGrant` is needed to allow us to apply a `SecurityPolicy` across namespaces to the CrowdSec bouncer:
```yaml
apiVersion: gateway.networking.k8s.io/v1beta1
kind: ReferenceGrant
metadata:
  name: homelab-envoy-proxy-bouncer
spec:
  from:
    - group: gateway.envoyproxy.io
      kind: SecurityPolicy
      namespace: blog
  to:
    - group: ""
      kind: Service
      name: homelab-envoy-proxy-bouncer
```

Then, we can apply a `SecurityPolicy` to the `HTTPRoute` for Ext Authz to send requests to the CrowdSec bouncer:
```yaml
apiVersion: gateway.envoyproxy.io/v1alpha1
kind: SecurityPolicy
metadata:
  labels:
    app: blog-prod
  name: blog-prod
  namespace: blog
spec:
  extAuth:
    grpc:
      backendRefs:
      - group: ""
        kind: Service
        name: homelab-envoy-proxy-bouncer
        namespace: envoy-gateway-system
        port: 8080
  targetRefs:
  - group: gateway.networking.k8s.io
    kind: HTTPRoute
    name: blog-prod
```

It is convenient to apply the `SecurityPolicy` on a per route basis because I can choose which routes are protected, such as the public internet exposed routes, while keeping routes that can only be accessed on my LAN policy free.

## Putting the Pieces Together

When an IP address makes a request to my blog, and there are no active decisions for that address, the flow looks something like the following:
![happy](/images/protecting-internet-facing-apps/happy.png)

In the case that a malicious IP makes a request to the blog, and a decision is cached, the request never makes it to the blog `Pod`
![ban](/images/protecting-internet-facing-apps/ban.png)

This flow allows exploits to be virtually patched without modifying the application code. I find this setup particularly useful for self-hosting because it can take time for applications to release new versions with security fixes.

In other cases, patching will be automatic as CrowdSec updates to collections you have installed.

In other cases, patches can be applied via [blocklists](https://app.crowdsec.net/blocklists/6666d5c9a5ded82be1bec1e0) in CrowdSec to block IPs that are exploiting a specific CVE.