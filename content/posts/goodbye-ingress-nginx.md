+++
author = "Kyle Wilson"
title = "Goodbye beloved ingress-nginx controller"
date = "2025-05-18"
description = "How I swapped to envoy gateway from ingress-nginx controller with the new Kuberenetes Gateway API"
summary = "How I swapped to envoy gateway from ingress-nginx controller with the new Kuberenetes Gateway API"
tags = [
    "Kubernetes",
    "Tailscale",
    "Envoy Gateway",
    "ingress-nginx",
    "envoy gateway",
    "cert-manager"
]
+++

## Why?

I've been using ingress-nginx for years now, and while I haven't had any complaints, it is soon to be replaced by [ingate](https://github.com/kubernetes-sigs/ingate). I'll probably give that a try when it's released, but until then I needed an alternative gateway controller.

Envoy Gateway is starting the process of being adopted at my workplace, so I wanted to get familiar with it and have an environemnt for testing.

I might as well get ahead of the curve and use the new Kubernetes Gateway API.

## Creating a gateway

The documentation for installing the gateway for envoy is pretty starghtforward. The documentation is [here](https://gateway.envoyproxy.io/docs/tasks/quickstart/). You don't need to have the gatewy api CRDs installed separately, they are shipped with the manifest in the documetation.

Assuming you have a working gateway controller deployed, we need to create a gateway class and gateway.

This gateway class definition will target the controller deployed in the previous step.
```yaml
apiVersion: gateway.networking.k8s.io/v1beta1
kind: GatewayClass
metadata:
  name: envoy-gateway-class
spec:
  controllerName: gateway.envoyproxy.io/gatewayclass-controller
```

A simple gateway definition, which will create a deployment and service to act as an ingress gateway, would look like the following. 

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: homelab
  namespace: envoy-gateway-system
spec:
  gatewayClassName: envoy-gateway-class
```
**NOTE:** The `gatewayClassName` field in the spec needs to match the name of the gateway class created above.

For my self-hosted services at home, I use a `*.int.kyledev.co` wildcard domain that is only exposed to my tailnet. This allows me to access them away from my home network without exposing them to the public internet.

With the tailscale operator installed, we can annotate our gateway with:
```yaml
tailscale.com/expose: "true"
tailscale.com/hostname: "homelab-gateway" # optional - sets the machine name in the tailnet
```

The service also needs to be of type `LoadBalancer` with a `loadBalancerClass` of type `tailscale` to expose it to the tailnet.

We can create an EnvoyProxy config for this gateway to expose it to the tailnet. This is essentially a template for a gateway to use so any gateway in the future can use it too.
```yaml
apiVersion: gateway.envoyproxy.io/v1alpha1
kind: EnvoyProxy
metadata:
  name: tailscale-proxy
spec:
  provider:
    type: "Kubernetes"
    kubernetes:
      envoyService:
        annotations:
          tailscale.com/expose: "true"
          tailscale.com/hostname: "homelab-gateway"
        loadBalancerClass: "tailscale"
        name: homelab-gateway
```

With the EnvoyProxy config created, we can configure the gateway to point to it
```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: homelab
  namespace: envoy-gateway-system
spec:
  gatewayClassName: envoy-gateway-class
  infrastructure:
    parametersRef:
      group: gateway.envoyproxy.io
      kind: EnvoyProxy
      name: tailscale-proxy
```

If we apply those gateway resources to the cluster, we should see something similar to:

```shell
$ k get gateway -n envoy-gateway-system
NAME      CLASS                 ADDRESS        PROGRAMMED   AGE
homelab   envoy-gateway-class   100.79.90.18   True         4d
```

```shell
$ k get svc -n envoy-gateway-system 
NAME              TYPE           CLUSTER-IP      EXTERNAL-IP                                     PORT(S)                                   AGE
envoy-gateway     ClusterIP      10.43.243.74    <none>                                          18000/TCP,18001/TCP,18002/TCP,19001/TCP   4d
homelab-gateway   LoadBalancer   10.43.216.210   100.79.90.18,homelab-gateway.tail18ac2.ts.net   80:31685/TCP,443:31965/TCP                3d1h
```

## Configuring the gateway

In my cluster, I have two setups:

A `*.kyledev.co` wildcard that is exposed to the public internet, and is served by a cloudflared tunnel to my cluster.

And as mentioned previously, `*.int.kyledev.co`, which resolves by running pihole on a machine that is connected to my tailnet. To use this I have to be connected to the tailnet.

On the pihole server, I create a dnsmasq config at `/etc/dnsmasq.d/99-tsnet.conf` where `100.79.90.18` is the tailnet IP of my envoy proxy tailscale machine
```shell
address=/int.kyledev.co/100.79.90.18
```

This will point anything that matches the `*.int.kyledev.co` wildcard to the tailnet IP of the gateway service exposed by the tailscale operator. 

I then override DNS for the machines on the tailnet to point to my pihole server. As a bonus, I also get tailnet-wide benefits of using pihole as a DNS server.

Next, I had 2 scenarios I wanted to cover:
```markdown
1. Automatic certificates for my domains
2. Allow HTTP + HTTPS traffic to *.kyledev.co and *.int.kyledev.co
```

### Automatic certificates

Luckily, `cert-manager` supports the gateway api already, and I was already using it for ingress resources. I use version `1.17.2` of cert-manager.

To enable the gateway api for `cert-manager`, we need to add this flag to the deployment of the controller
```shell
--enable-gateway-api
```

My full deployment looks like this for the controller:
{{< details "deployment.yaml" >}}
```yaml
# Source: cert-manager/templates/deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: cert-manager
  namespace: cert-manager
  labels:
    app: cert-manager
    app.kubernetes.io/name: cert-manager
    app.kubernetes.io/instance: cert-manager
    app.kubernetes.io/component: "controller"
    app.kubernetes.io/version: "v1.17.2"
spec:
  replicas: 1
  selector:
    matchLabels:
      app.kubernetes.io/name: cert-manager
      app.kubernetes.io/instance: cert-manager
      app.kubernetes.io/component: "controller"
  template:
    metadata:
      labels:
        app: cert-manager
        app.kubernetes.io/name: cert-manager
        app.kubernetes.io/instance: cert-manager
        app.kubernetes.io/component: "controller"
        app.kubernetes.io/version: "v1.17.2"
      annotations:
        prometheus.io/path: "/metrics"
        prometheus.io/scrape: 'true'
        prometheus.io/port: '9402'
    spec:
      serviceAccountName: cert-manager
      enableServiceLinks: false
      securityContext:
        runAsNonRoot: true
        seccompProfile:
          type: RuntimeDefault
      containers:
        - name: cert-manager-controller
          image: "quay.io/jetstack/cert-manager-controller:v1.17.2"
          imagePullPolicy: IfNotPresent
          args:
          - --v=2
          - --cluster-resource-namespace=$(POD_NAMESPACE)
          - --leader-election-namespace=kube-system
          - --acme-http01-solver-image=quay.io/jetstack/cert-manager-acmesolver:v1.17.2
          - --max-concurrent-challenges=60
          - --enable-gateway-api # new flag
          ports:
          - containerPort: 9402
            name: http-metrics
            protocol: TCP
          - containerPort: 9403
            name: http-healthz
            protocol: TCP
          securityContext:
            allowPrivilegeEscalation: false
            capabilities:
              drop:
              - ALL
            readOnlyRootFilesystem: true
          env:
          - name: POD_NAMESPACE
            valueFrom:
              fieldRef:
                fieldPath: metadata.namespace
          # LivenessProbe settings are based on those used for the Kubernetes
          # controller-manager. See:
          # https://github.com/kubernetes/kubernetes/blob/806b30170c61a38fedd54cc9ede4cd6275a1ad3b/cmd/kubeadm/app/util/staticpod/utils.go#L241-L245
          livenessProbe:
            httpGet:
              port: http-healthz
              path: /livez
              scheme: HTTP
            initialDelaySeconds: 10
            periodSeconds: 10
            timeoutSeconds: 15
            successThreshold: 1
            failureThreshold: 8
      nodeSelector:
        kubernetes.io/os: linux
```
{{< /details >}}

Then you can can annotate the gateway with `cert-manager.io/cluster-issuer: <your-issuer-name>` to automatically provision certificates for us with an issuer of choice.

Because I use multiple dns names, I created a certificate for the wildcard domain manually
```yaml
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: kyledev-wildcard-tls
  namespace: envoy-gateway-system
spec:
  secretName: kyledev-tls
  issuerRef:
    name: letsencrypt-prod
    kind: ClusterIssuer
  commonName: "*.kyledev.co"
  dnsNames:
    - "*.kyledev.co"
    - "*.int.kyledev.co"
```

### Traffic Configuration

Each gateway can be configured with an array of listeners which allows fine grained control over the traffic that is routed to the gateway.

In my setup, I needed to create 2 listeners for the scenarios I outlined above.
```markdown
1. `*.kyledev.co` needs to receive HTTP and HTTPS traffic with a specific certificate
2. `*.int.kyledev.co` needs to receive HTTPS traffic with a specific certificate
```

In both of these scenarios, I wanted to be able to create HTTPRoutes from any namespace, and let the gateway handle terminating TLS.

The certificateRefs are the secrets that cert-manager will create if you annotate the gateway with `cert-manager.io/cluster-issuer`.

If you're not using cert-manager (or any other automation), you need to create the secrets manually like I did above.

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: homelab
  namespace: envoy-gateway-system
spec:
  gatewayClassName: envoy-gateway-class
  infrastructure:
    parametersRef:
      group: gateway.envoyproxy.io
      kind: EnvoyProxy
      name: tailscale-proxy
  listeners:
    - name: kyledev-http
      protocol: HTTP
      port: 80
      hostname: "*.kyledev.co"
      allowedRoutes:
        namespaces:
          from: All
    - name: kyledev-https
      protocol: HTTPS
      port: 443
      hostname: "*.kyledev.co"
      allowedRoutes:
        namespaces:
          from: All
      tls:
        mode: Terminate
        certificateRefs:
          - name: kyledev-tls
            kind: Secret
            group: ""
```

## Testing it out

We need to create a `HTTPRoute` resource for each of the scenarios we want to test.

This is pretty straightforward
```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: blog-public
  namespace: blog
spec:
  parentRefs:
    - name: homelab # name of the gateway
      namespace: envoy-gateway-system # name of the gateway namespace
  hostnames:
    - "blog.kyledev.co"
  rules:
    - backendRefs:
        - name: blog
          port: 80
```

This blog, for example, is now exposed from my cluster using the gateway api. You can see the `HTTPRoute` resources for
- [dev](https://github.com/kdwils/blog/blob/dev/deploy/dev/httproute.yaml) internally used in my tailnet for testing purposes `blog.int.kyledev.co`
- [prod](https://github.com/kdwils/blog/blob/prod/deploy/prod/httproute.yaml) for the "battle-tested" changes at `blog.kyledev.co`, which is what you're reading right now

For some traffic I expose to the public internet, I use cloudflared to create a tunnel to my cluster. 

I did a previous post on that setup [here](/posts/cloudflare-tunnel). My tunnel configuration for the public instance of my blog is [here](https://github.com/kdwils/homelab/blob/main/infra/cloudflared/configmap.yaml#L13-L14). The tl;dr is point the hostname to the envoy-gateway service.

Once the `HTTPRoute` resources were created, I was able to resolve my blog at `blog.kyledev.co` and `blog.int.kyledev.co`