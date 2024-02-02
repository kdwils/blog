+++
author = "Kyle Wilson"
title = "Gatekeeping with OPA Gatekeeper"
date = "2024-02-02"
description = "Enforcing policy for kubernetes deployments with OPA Gatekeeper"
summary = "Enforcing policy for kubernetes deployments with OPA Gatekeeper"
tags = [
    "Open Policy Agent",
    "Kubernetes"
]
+++

## What is Gatekeeper?

[Gatekeeper](https://github.com/open-policy-agent/gatekeeper) is a controller for kubernetes deployments built on top of OPA for describing and enforcing policy. See [here](https://open-policy-agent.github.io/gatekeeper/website/docs/) for more information.

OPA is a [CNCF graduated project](https://www.cncf.io/projects/open-policy-agent-opa/) and is the policy engine I use at work. It uses a language known as rego for policy definitions.

## How does it work at a high level?

The gatekeeping piece of gatekeeper is done through admission webhooks. When a resource is created, modified, or deleted, these actions can be validated by executing the change against an admission webhook. The webhook can then decide whether to allow, or to reject, the incoming resource.

## Installation

I deployed gatekeeper using a raw manifest from their installation docs. The configurations live in my [homelab repository](https://github.com/kdwils/homelab/tree/main/gatekeeper), and are synced to my home cluster via an [argocd application](https://github.com/kdwils/homelab/blob/main/apps/gatekeeper-app.yaml).

The installation docs can be found [here](https://open-policy-agent.github.io/gatekeeper/website/docs/install).

## Templates, Constraints, and Syncs
Templates, Constraints, and Syncs make up the core functionality for Gatekeeper. A full library of preconfigured policies can be found in the [gatekeeper library repo](https://github.com/open-policy-agent/gatekeeper-library/tree/master/library/general).

### Templates
Templates contain the logic for determining whether a manifest is violating policy. The template CRD is responsible for creating another CRD for the policy you want to enforce. Additionally, the template contains the actual rego code for the policy.

An example template I currently use in my home cluster is for blocking duplicate ingress hosts. I find myself copying and pasting ingresses a lot because they don't change much between my services with the exception of the host and tls secret. This often leads to cases where copy pasta breaks my deployment.

This is an example template provided by the [Gatekeeer policy library](https://github.com/open-policy-agent/gatekeeper-library/blob/master/library/general/uniqueingresshost/template.yaml).

{{< details "Duplicate Hosts Template" >}}

```yaml
apiVersion: templates.gatekeeper.sh/v1
kind: ConstraintTemplate
metadata:
  name: k8suniqueingresshost
  annotations:
    metadata.gatekeeper.sh/title: "Unique Ingress Host"
    metadata.gatekeeper.sh/version: 1.0.4
    metadata.gatekeeper.sh/requires-sync-data: |
      "[
        [
          {
            "groups": ["extensions"],
            "versions": ["v1beta1"],
            "kinds": ["Ingress"]
          },
          {
            "groups": ["networking.k8s.io"],
            "versions": ["v1beta1", "v1"],
            "kinds": ["Ingress"]
          }
        ]
      ]"
    description: >-
      Requires all Ingress rule hosts to be unique.

      Does not handle hostname wildcards:
      https://kubernetes.io/docs/concepts/services-networking/ingress/
spec:
  crd:
    spec:
      names:
        kind: K8sUniqueIngressHost
  targets:
    - target: admission.k8s.gatekeeper.sh
      rego: |
        package k8suniqueingresshost

        identical(obj, review) {
          obj.metadata.namespace == review.object.metadata.namespace
          obj.metadata.name == review.object.metadata.name
        }

        violation[{"msg": msg}] {
          input.review.kind.kind == "Ingress"
          regex.match("^(extensions|networking.k8s.io)$", input.review.kind.group)
          host := input.review.object.spec.rules[_].host
          other := data.inventory.namespace[_][otherapiversion]["Ingress"][name]
          regex.match("^(extensions|networking.k8s.io)/.+$", otherapiversion)
          other.spec.rules[_].host == host
          not identical(other, input.review)
          msg := sprintf("ingress host conflicts with an existing ingress <%v>", [host])
        }
```
{{< /details >}}

### Syncs
Its not always as simple as enforcing policy that requires a deploy to have at least 2 replicas in a static manifest.

In the case of wanting to enforce unique hostnames in Ingress resources, we need to also look at other Ingress resources in the kubernetes cluster. This is where [sync configurations](https://open-policy-agent.github.io/gatekeeper/website/docs/sync/) are needed.

In the case of checking ingress hostnames, we need to tell Gatekeeper to cache Ingress resources. We want to be thorough and include all groups/versions available for Ingress resources to be cached so that none can slip by.

With the resources synced into Gatekeeper, we can then run enforce policy with those resources also in consideration.



{{< details "Sync configuration for Ingress resource" >}}
```yaml
apiVersion: config.gatekeeper.sh/v1alpha1
kind: Config
metadata:
  name: config
  namespace: "gatekeeper-system"
spec:
  sync:
    syncOnly:
      - group: "networking.k8s.io"
        version: "v1"
        kind: "Ingress"
      - group: "extensions"
        version: "v1beta1"
        kind: "Ingress"
      - group: "networking.k8s.io"
        version: "v1beta1"
        kind: "Ingress"
```
{{< /details >}}

### Constraints

Constraints tell Gatekeeper what resources to enforce policy against. Kubernetes resources that match the constraint definition are subjecto to policy enforcement.

For our unique ingress example, our constraint looks like this:

{{< details "Constraint definition for Ingress resources" >}}
```yaml
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sUniqueIngressHost
metadata:
  name: unique-ingress-host
spec:
  match:
    kinds:
      - apiGroups: ["extensions", "networking.k8s.io"]
        kinds: ["Ingress"]
```
{{< /details >}}

## Testing
Gatekeeper has a CLI solution for running tests against your constraints and templates called [Gator](https://open-policy-agent.github.io/gatekeeper/website/docs/gator/).

Gator will look for a suite configuration that ties all of the pieces needed to test together. For my unique ingress host policy, I have the following suite defined:

{{< details "Suite resource for testing policy enforcement" >}}
```yaml
kind: Suite
apiVersion: test.gatekeeper.sh/v1alpha1
metadata:
  name: uniqueingresshost
tests:
  - name: unique-ingress-host
    template: template.yaml
    constraint: constraint.yaml
    cases:
      - name: allowed
        object: tests/unique-host.yaml
        assertions:
          - violations: no
      - name: duplicate
        object: tests/duplicate-host.yaml
        inventory:
          - tests/duplicate-host-inventory.yaml
        assertions:
          - violations: yes
```
{{< /details >}}

The actual test resources can be found [here](https://github.com/kdwils/homelab/tree/main/gatekeeper/policy/block-duplicate-ingress-hosts/tests).

For some cases, you need to "preload" data for the test for real world scenarios, such as an Ingress with a specific host that already exists.

The inventory field on each test exists for that purpose. For a duplicate test, we preload an ingress resource into the test, and then the test itself has another ingress defined with the same host. The expected result is a violation of policy, which is defined in the assertions field.

To run all tests, we can use the gator cli `gator verify ./...`.

```bash
❯ gator verify ./...
ok      homelab/gatekeeper/policy/block-duplicate-ingress-hosts/suite.yaml     0.011s
PASS
```

These can also be ran as a part of pipeline validations similar to any other unit tests that run during CI for building artifacts.

# Trying it out for real

Gatekeeper is expected to.. gatekeep deployments that violate policy. Lets try it out.

First, we can apply an ingress with a unique host.

{{< details "Test ingress - allowed" >}}
```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: ingress-host-allowed
  namespace: test
spec:
  rules:
    - host: example-host.example.com
      http:
        paths:
          - pathType: Prefix
            path: "/"
            backend:
              service:
                name: nginx
                port:
                  number: 80
```

```bash
❯ cat tests/allowed-host.yaml| k apply -f -
ingress.networking.k8s.io/ingress-host-allowed created
```
{{< /details >}}


Next, we try to create an Ingress resource with the same host name as the previous Ingress.

{{< details "Test ingress - disallowed" >}}
```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: ingress-host-disallowed
  namespace: test
spec:
  rules:
    - host: example-host.example.com
      http:
        paths:
          - pathType: Prefix
            path: "/"
            backend:
              service:
                name: nginx
                port:
                  number: 80
```

```bash
❯ cat tests/duplicate-host.yaml| k apply -f - 
Error from server (Forbidden): error when creating "STDIN": admission webhook "validation.gatekeeper.sh" denied the request: [unique-ingress-host] ingress host conflicts with an existing ingress <example-host.example.com>
```
{{< /details >}}

Policy enforcement works as expected.

## What about resources that are already deployed to my cluster?

Gatekeeper provides functionality for viewing resources that are currently violating policy. There is documentation around this topic [here](https://open-policy-agent.github.io/gatekeeper/website/docs/audit/).

It seems that the default behavior is to store the violations in memory, but there is alpha functionality for exporting violations via pubsub. This could be used to export violations to a pubsub topic for a more permanent storage solution.

## Closing thoughts

While the policy enforcement for gatekeeper works as expected, the way the rego is handled feels awkward.

The raw rego living within the template CRD itself seems like it could become a problem. In more complex policy scenarios, I feel that the rego might get messier to work with the CRD. While I don't have any solutions for solving this, one thought I had would be to point to a remote resource that is not a CRD, but rather the rego file itself. Another solution might be some type of templating flow.

One caveat I noticed with using ArgoCD to sync Gatekeeper and policy to my cluster is that the Template needs to be applied first in order to create the CRD resource your constraints. Without it, the constraint cannot be applied as the constraint points to the CRD resource.

The solution here is to use sync waves with argo to first apply the template followed by the constraint. This can be achieved using the sync-wave annotation provided by ArgoCD.

{{< details "Using sync waves" >}}
```yaml
apiVersion: templates.gatekeeper.sh/v1
kind: ConstraintTemplate
metadata:
  name: k8sblockwildcardingress
  annotations:
    argocd.argoproj.io/sync-wave: "1"
```

```yaml
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sBlockWildcardIngress
metadata:
  name: block-wildcard-ingress
  annotations:
    argocd.argoproj.io/sync-wave: "2"
```
{{< /details >}}

### For the future 

Overall, I plan on using Gatekeeper to keep myself from applying misconfigured resources to my homelab, and exploring future solutions to handling the rego policy definitions. 