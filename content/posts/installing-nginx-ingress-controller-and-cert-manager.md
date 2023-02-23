+++
author = "Kyle Wilson"
title = "Setting up ingress-nginx-controller and cert-manager"
date = "2023-02-20"
description = "Setting up ingress-nginx-controller and cert-manager using DNS-01 challenge with cloudflare. We'll be using our pihole deployment for local DNS lookups pointing to our new ingress point."
summary = "Setting up ingress-nginx-controller and wildcard certificates using cert-manager DNS-01 challenge with cloudflare. We'll be using our pihole deployment for local DNS lookups pointing to our new ingress controller."
tags = [
    "homelab",
    "ingress-nginx-controller",
    "cert-manager",
    "letsencrypt",
    "reflector"
]
+++

## Reflector

[Reflector](https://github.com/emberstack/kubernetes-reflector) is a Kubernetes addon designed to monitor changes to resources (secrets and configmaps) and reflect changes to mirror resources in the same or other namespaces.

We want to create a wildcard certificate for our cluster, and have that secret replicated across all the namespaces that needs the certificate.

### Installation

{{< highlight bash >}}
$ kubectl -n kube-system apply -f https://github.com/emberstack/kubernetes-reflector/releases/latest/download/reflector.yaml

serviceaccount/reflector created
clusterrole.rbac.authorization.k8s.io/reflector created
clusterrolebinding.rbac.authorization.k8s.io/reflector created
deployment.apps/reflector created
{{< /highlight >}}

{{< highlight bash >}}
$ kubectl get pods -n kube-system

NAME                                        READY   STATUS    RESTARTS   AGE
local-path-provisioner-79f67d76f8-6jh6f     1/1     Running   0          5d23h
coredns-597584b69b-69tdx                    1/1     Running   0          5d23h
metrics-server-5f9f776df5-cdm9t             1/1     Running   0          5d23h
reflector-5c99b9b7c9-tbdbn                  1/1     Running   0          6m27s
{{< /highlight >}}

Looks good to go.

## Cert Manager

Cert-manager adds certificates and certificate issuers as resource types in Kubernetes clusters, and simplifies the process of obtaining, renewing and using those certificates. Checkout out the [docs](https://cert-manager.io/docs/) for more information.


### Installation

I'll be installing cert-manager using a manifest, but feel free to follow the [docs](https://cert-manager.io/docs/installation/) for other options such as helm.

{{< highlight bash >}}
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.11.0/cert-manager.yaml
{{< /highlight >}}

Verify the installation. I've had cert-manager installed for a few days now.

{{< highlight bash >}}
$ kubectl get pods -n cert-manager

NAME                                      READY   STATUS    RESTARTS   AGE
cert-manager-cainjector-ffb4747bb-g5jqp   1/1     Running   0          5d21h
cert-manager-webhook-545bd5d7d8-tzhzd     1/1     Running   0          5d21h
cert-manager-7dfffc7574-hdcqs             1/1     Running   0          4d23h
{{< /highlight >}}

### LetsEncrypt Challenges

We'll be using [LetsEncrypt](https://letsencrypt.org/) as our Certificate Authority.

In order to be issued a certificate, we need to complete a challenge. There are two challenge options we can complete. Cert-Manager can be configured to attempt either of the two challenges.

#### HTTP-01 Challenge
For the [HTTP-01](https://letsencrypt.org/docs/challenge-types/#http-01-challenge) Lets Encrypt gives a token to your ACME client, and your ACME client puts a file on your web server at `http://<YOUR_DOMAIN>/.well-known/acme-challenge/<TOKEN>`.

This assumes that your cluster is externally reachable, which ours is not, so we'll not be going this route.

#### DNS-01 Challenge
The [DNS-01](https://letsencrypt.org/docs/challenge-types/#dns-01-challenge) asks you to prove that you control the DNS for your domain name by putting a specific value in a TXT record under that domain name. Our cluster does not have to be externally reachable to perform this challenge.

LetsEncrypt has a list of supported [providers](https://cert-manager.io/docs/configuration/acme/dns01/#supported-dns01-providers) we can use. We'll be using cloudflare.

#### Creating a cluster issuer using Cloudflare for DNS-01

We'll be following the [docs](https://cert-manager.io/docs/configuration/acme/dns01/cloudflare/) for using cloudflare.

First, we need to create a secret for our cloudflare API token.
{{< highlight yaml >}}
$ cat cloudflare-api-token-secret.yaml

apiVersion: v1
kind: Secret
metadata:
  name: cloudflare-api-token-secret
  namespace: cert-manager
type: Opaque
stringData:
  api-token: <your-api-token>
{{< /highlight >}}

Next, we'll need to create a `ClusterIssuer` to handle issuing certificates. We've configured our issuer to use DNS-01 with cloudflare as our provider, referencing the cloudflare token secret we created a few moments ago.

LetsEncrypt has a staging API we can use for testing our cluster issuer setup. We'll create a staging issuer first to test our configurations.

{{< highlight yaml >}}
$ cat cluster-issuer-staging.yaml

apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-staging
spec:
  acme:
    server: https://acme-staging-v02.api.letsencrypt.org/directory
    email: <your-email>
    privateKeySecretRef:
      name: letsencrypt-staging
    solvers:
      - dns01:
          cloudflare:
            email: <your-email>
            apiTokenSecretRef:
              name: cloudflare-api-token-secret
              key: api-token
{{< /highlight >}}

Verify your ClusterIssuer is ready to go.

{{< highlight bash >}}
$ kubectl get clusterissuer -n cert-manager

NAME                  READY   AGE
letsencrypt-staging   True    5d21h
{{< /highlight >}}

I want the certificate secret to be created in the namespace `go-hello`, so go ahead and create that namespace now if you're following along.

{{< highlight bash >}}
$ kubectl create namespace go-hello

namespace/go-hello created
{{< /highlight >}}

Next, the wildcard certificate.

We need to tell `reflector` which namespaces to replicate the tls secret to. Check out the `secretTemplate` in our certificate.

{{< highlight yaml >}}
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: wildcard-kyledev-tls-staging
  namespace: cert-manager
spec:
  secretName: wildcard-kyledev-tls-staging
  issuerRef:
    name: letsencrypt-staging
    kind: ClusterIssuer
  secretTemplate:
    annotations:
      reflector.v1.k8s.emberstack.com/reflection-allowed: "true"
      reflector.v1.k8s.emberstack.com/reflection-allowed-namespaces: "go-hello"
      reflector.v1.k8s.emberstack.com/reflection-auto-enabled: "true"
  commonName: "*.kyledev.co"
  dnsNames:
    - "*.kyledev.co"
    - "*.int.kyledev.co"
{{< /highlight >}}

Wait for your certificate to become ready. `Reflector` should create the certificate secret in our `go-hello` namespace automatically.

{{< highlight bash >}}
$ kubectl get cert -n cert-manager
NAME                           READY   SECRET                         AGE
wildcard-kyledev-tls-staging   True    wildcard-kyledev-tls-staging   15s

$ kubectl get secret -n go-hello
NAME                           TYPE                DATA   AGE
wildcard-kyledev-tls-staging   kubernetes.io/tls   2      36s
{{< /highlight >}}


## Ingress-nginx

We'll be using [ingress-nginx](https://kubernetes.github.io/ingress-nginx/) as our ingress controller. An Ingress controller is a specialized load balancer for Kubernetes (and other containerized) environments.

### Installation

Feel free to follow the [docs](https://kubernetes.github.io/ingress-nginx/deploy/) to figure out installation for your cluster.

I'll be installing via manifest, again.

Assuming you've set up loadbalancing, such as metallb, we'll be going with the cloud provider manifest so we can expose the ingress controller via external-ip.

Check out how to [install metallb](/posts/installing-metallb-on-k3s-rpi-cluster-with-tailscale/) if you're interested.

{{< highlight bash >}}
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.6.4/deploy/static/provider/cloud/deploy.yaml
{{< /highlight >}}


Verify the ingress controller is up and running
{{< highlight bash >}}
$ kubectl get pods -n ingress-nginx
NAME                                        READY   STATUS      RESTARTS   AGE
ingress-nginx-admission-patch-hmf9z         0/1     Completed   0          4d22h
ingress-nginx-admission-create-bwzpg        0/1     Completed   0          4d22h
ingress-nginx-controller-6b94c75599-plj2z   1/1     Running     0          4d22h

$ kubectl get svc -n ingress-nginx
NAME                                 TYPE           CLUSTER-IP      EXTERNAL-IP   PORT(S)                      AGE
ingress-nginx-controller             LoadBalancer   10.43.142.121   10.0.1.0      80:32628/TCP,443:32568/TCP   4d22h
ingress-nginx-controller-admission   ClusterIP      10.43.85.161    <none>        443/TCP                      4d22h
{{< /highlight >}}

Notice how metallb assigned an external-ip `10.0.1.0` to the ingress controller. Remember this guy for later.

Our ingress controller is set up and good to go.

## Pihole for Local DNS

If you haven't set up pihole yet, checkout this [post](/posts/installing-metallb-on-k3s-rpi-cluster-with-tailscale/#pihole). The rest of this post is heavily based on the linked setup.

We're going to be updating our pihole deployment for local dns lookups with our domain `kyledev.co`. For my internal services, I want to access them via `*.int.kyledev.co`.

Let's update our custom dnsmasq for pihole to point `int.kyledev.co` to our new ingress-nginx-controller external-ip of `10.0.1.0`.

{{< highlight yaml >}}
apiVersion: v1
kind: ConfigMap
metadata:
  name: homelab-pihole-custom-dnsmasq
  labels:
    app: pihole
    chart: pihole-2.11.1
    release: homelab
    heritage: Helm
data:
  02-custom.conf: |
    addn-hosts=/etc/addn-hosts
    address=/int.kyledev.co/10.0.1.0
  addn-hosts: |
  05-pihole-custom-cname.conf: |
{{< /highlight >}}

Delete the running pihole pod so it picks up the new config map changes.

{{< highlight bash >}}
$ kubectl get pods -n pihole
NAME                             READY   STATUS    RESTARTS   AGE
homelab-pihole-989bd4c59-vf9kb   1/1     Running   0          2d19h

$ kubectl delete pod/homelab-pihole-989bd4c59-vf9kb -n pihole
pod "homelab-pihole-989bd4c59-vf9kb" deleted

$ kubectl get pods -n pihole
NAME                             READY   STATUS    RESTARTS   AGE
homelab-pihole-989bd4c59-jjdcj   0/1     Running   0          9s
{{< /highlight >}}

## Testing it all out

We'll be deploying a sample hello world service to test it all out. We'll be using a [go service](https://github.com/kdwils/go-hello) I used for testing out CI/CD with tailscale and github actions. I'll probably create a post for this later.

First, lets note the annotations on the Ingress.

`cert-manager.io/cluster-issuer: letsencrypt-staging` tells our `ClusterIssuer` to issue a certificate for this ingress. Notice we are pointing to our staging ClusterIssuer. We'll create a production issuer after we validate our staging issuer.

`kubernetes.io/ingress.class: nginx` tells our `ingress-nginx-controller` it will be managing this ingress.

Additionally, we're pointing to our wildcard staging certificate `wildcard-kyledev-tls-staging`
{{< highlight yaml >}}
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-staging
    kubernetes.io/ingress.class: nginx
  name: go-hello
  namespace: go-hello
spec:
  rules:
  - host: go-hello.int.kyledev.co
    http:
      paths:
      - backend:
          service:
            name: go-hello
            port:
              name: http
        path: /
        pathType: Prefix
  tls:
  - hosts:
    - go-hello.int.kyledev.co
    secretName: wildcard-kyledev-tls-staging
{{< /highlight >}}

Heres the full kubernetes yaml for the deployment, including the ingress.

{{< details "Hello World YAML" >}}
{{< highlight yaml >}}
apiVersion: v1
kind: Service
metadata:
  name: go-hello
  namespace: go-hello
spec:
  ports:
  - name: http
    port: 80
    targetPort: 8080
  selector:
    app: go-hello
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: go-hello
  namespace: go-hello
spec:
  selector:
    matchLabels:
      app: go-hello
  template:
    metadata:
      labels:
        app: go-hello
    spec:
      containers:
      - image: ghcr.io/kdwils/go-hello:aa0c06eb9ecf122693445393216b177ee800fc18
        imagePullPolicy: Always
        name: go-hello
        ports:
        - containerPort: 8080
          name: http
        resources:
          limits:
            cpu: 500m
            memory: 128Mi
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-staging
    kubernetes.io/ingress.class: nginx
  name: go-hello
  namespace: go-hello
spec:
  rules:
  - host: go-hello.int.kyledev.co
    http:
      paths:
      - backend:
          service:
            name: go-hello
            port:
              name: http
        path: /
        pathType: Prefix
  tls:
  - hosts:
    - go-hello.int.kyledev.co
    secretName: wildcard-kyledev-tls-staging
{{< /highlight >}}
{{< /details >}}

Deploy the hello world service to your cluster.

{{< highlight bash >}}
$ kubectl apply -f hello-world.yaml

service/go-hello created
deployment.apps/go-hello created
ingress.networking.k8s.io/go-hello created

$ kubectl get pods -n go-hello

NAME                        READY   STATUS    RESTARTS   AGE
go-hello-654db7765c-jsx7s   1/1     Running   0          3m27s
{{< /highlight >}}

Check out the ingress as well. Notice how the address is the same as our ingress-nginx-controller load balancer.

{{< highlight bash >}}
$ kubectl get ingress -n go-hello

NAME       CLASS    HOSTS                     ADDRESS    PORTS     AGE
go-hello   <none>   go-hello.int.kyledev.co   10.0.1.0   80, 443   3m51s
{{< /highlight >}}

And we can head over to `go-hello.int.kyledev.co` to verify everything is working.

But theres a problem...https isn't working? That's because we're using the staging LetsEncrypt certificate.

![insecure](/images/nginx-ingress/staging-cert.png)

## LetsEncrypt prod issuer
Lets set up our prod issuer since we can see that our staging issuer is working as intended.

{{< highlight yaml >}}
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: <your-email>
    privateKeySecretRef:
      name: letsencrypt-prod
    solvers:
      - dns01:
          cloudflare:
            email: <your-email>
            apiTokenSecretRef:
              name: cloudflare-api-token-secret
              key: api-token
{{< /highlight >}}

Followed by our prod wildcard certificate.

{{< highlight yaml >}}
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: wildcard-kyledev-tls-prod
  namespace: cert-manager
spec:
  secretName: wildcard-kyledev-tls-prod
  issuerRef:
    name: letsencrypt-prod
    kind: ClusterIssuer
  secretTemplate:
    annotations:
      reflector.v1.k8s.emberstack.com/reflection-allowed: "true"
      reflector.v1.k8s.emberstack.com/reflection-allowed-namespaces: "go-hello"
      reflector.v1.k8s.emberstack.com/reflection-auto-enabled: "true"
  commonName: "*.kyledev.co"
  dnsNames:
    - "*.kyledev.co"
    - "*.int.kyledev.co"
{{< /highlight >}}

Our updated ingress will look largely the same, however we'll point to our new prod `ClusterIssuer` with the annotation `cert-manager.io/cluster-issuer: letsencrypt-prod`. Additionally, we need to point to he new tls secret `wildcard-kyledev-tls-prod`.

{{< highlight yaml >}}
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod
    kubernetes.io/ingress.class: nginx
  name: go-hello
  namespace: go-hello
spec:
  rules:
  - host: go-hello.int.kyledev.co
    http:
      paths:
      - backend:
          service:
            name: go-hello
            port:
              name: http
        path: /
        pathType: Prefix
  tls:
  - hosts:
    - go-hello.int.kyledev.co
    secretName: wildcard-kyledev-tls-prod
{{< /highlight >}}

And it should magically work!

![secure](/images/nginx-ingress/prod-cert.png)

# Whats Next?

Interested in how I deploy my blog? Take a peek at how I used a [cloudflare tunnel](/posts/exposing-my-blog-using-a-cloudflare-tunnel/).