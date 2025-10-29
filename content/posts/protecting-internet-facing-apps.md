+++
author = "Kyle Wilson"
title = "How I protect Kubernetes services with CrowdSec"
date = "2025-10-28"
description = "A high-level overview of protecting Kubernetes services using CrowdSec, Envoy Gateway, Cloudflared Tunnel, and a custom Envoy Proxy Bouncer to detect and block malicious traffic."
summary = "Learn how to protect internet-facing Kubernetes applications by combining CrowdSec's threat intelligence with Envoy Gateway's external authorization. This setup enables automatic blocking of malicious IPs and virtual patching of vulnerabilities without modifying application code."
tags = [
    "homelab",
    "crowdsec",
    "envoy-gateway"
]
+++

## Fear of the Unknown

Exposing applications to the internet is risky, and I wanted to have *some* insight into who is making requests and what they are requesting.

After discovering CrowdSec, I realized there was an opportunity to write a remediation component for Envoy Proxy since one didn't exist yet.

In my last two blog posts, I covered the [`envoy-proxy` remediation component](https://github.com/kdwils/envoy-proxy-crowdsec-bouncer) I wrote. Those posts focused on the bouncer functionality, and in this post I want to cover the other pieces that come together to make the entire process work.

## The Components

The solution combines three main components: Cloudflared Tunnel, CrowdSec, and Envoy Gateway.

The logic in the remediation component is straightforward: parse the real IP of the request, check the decision cache, and apply the decision if one exists (block the request or serve a captcha).

### Cloudflared Tunnel

Cloudflared Tunnel acts as a safe ingress for services in my Kubernetes cluster. I won't go over the details of setting up Cloudflared in this post as I've already covered it in a [previous post](/posts/cloudflare-tunnel). My setup has changed since then, but the core concept remains the same.

The tunnel allows me to keep my IP private since users only see a Cloudflare IP. I also don't have to configure port forwarding on my router.

We need to configure the tunnel to route traffic to Envoy Gateway. I'm choosing to terminate TLS at the gateway and need to ensure SNI works correctly for my wildcard certificate.

```yaml
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

### CrowdSec

The CrowdSec [Local API](https://docs.crowdsec.net/docs/local_api/intro/) exposes endpoints for streaming live decision updates to remediation components. Decisions are tied to IP addresses and instruct remediation components on what action to take (captcha, ban, etc.) when an incoming request matches a decision.

The Envoy Proxy remediation component consumes from this stream on startup, caching all existing decisions locally so they can be applied immediately to incoming requests without additional API calls.

### Envoy Gateway

Envoy Gateway acts as the ingress for all services in my cluster, including both internal and internet-exposed applications. Envoy Gateway implements the Kubernetes Gateway API, and since communication to my blog Pod is made over HTTP, we use an `HTTPRoute`.

The `HTTPRoute` defines how traffic for specific hostnames gets routed to backend services. Here's the configuration for my blog:
```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  labels:
    app: blog
  name: blog
  namespace: blog
spec:
  hostnames:
  - blog.kyledev.co
  parentRefs:
  - name: homelab
    namespace: envoy-gateway-system
  rules:
  - backendRefs:
    - name: blog
      port: 80
```

To enable CrowdSec protection, we need to apply a `SecurityPolicy` to this route. However, the bouncer runs in a different namespace (`envoy-gateway-system`) than the blog (`blog` namespace).

The Gateway API security model requires explicit permission for cross-namespace references. A `ReferenceGrant` provides this permission, allowing the `SecurityPolicy` in the `blog` namespace to reference the bouncer service in `envoy-gateway-system`:
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

With the `ReferenceGrant` in place, we can now apply a `SecurityPolicy` to the `HTTPRoute`. This policy configures Envoy Gateway's external authorization feature to validate each request with the CrowdSec bouncer via gRPC before forwarding traffic to the blog:
```yaml
apiVersion: gateway.envoyproxy.io/v1alpha1
kind: SecurityPolicy
metadata:
  labels:
    app: blog
  name: blog
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
    name: blog
```

Applying the `SecurityPolicy` on a per-route basis is convenient because I can choose which routes are protected, such as internet-exposed routes, while keeping LAN-only routes policy-free.

## How It All Works Together

Now that we've covered each component individually, let's see how they work together to protect applications from malicious traffic.

When an IP address makes a request to my blog and there are no active decisions for that address, the flow looks like this:
[![happy](/images/protecting-internet-facing-apps/happy.png)](/images/protecting-internet-facing-apps/happy.png)

When a malicious IP makes a request to the blog and cached decision on the bouncer matches the IP, the request never makes it to the blog:
[![ban](/images/protecting-internet-facing-apps/ban.png)](/images/protecting-internet-facing-apps/ban.png)

This flow enables virtual patching of exploits without modifying application code. This is particularly useful for self-hosting, where open source applications may take time to release security fixes (assuming they're even aware of the vulnerability).

In some cases, patching happens automatically as CrowdSec updates the collections installed on your instance.

In other cases, patches can be applied manually via CrowdSec [blocklists](https://app.crowdsec.net/blocklists/6666d5c9a5ded82be1bec1e0) to block IPs exploiting specific CVEs.

## Conclusion

If you're interested in implementing this solution, check out the [envoy-proxy-crowdsec-bouncer repository](https://github.com/kdwils/envoy-proxy-crowdsec-bouncer) on GitHub.