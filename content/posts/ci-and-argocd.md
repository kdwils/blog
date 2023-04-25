+++
author = "Kyle Wilson"
title = "How I deploy applications to my cluster using github actions and argocd"
date = "2023-04-25"
description = "How I deploy applications to my cluster using github actions and argocd"
summary = "How I deploy applications to my cluster using github actions and argocd"
tags = [
    "github actions",
    "argocd",
    "CI",
    "CD"
]
+++

## CI and CD

At work, we follow the practice of a separate code repo and deployment repo for `CI` and `CD`. This allows for the decoupling of code and configurations for deployment. However, in my home cluster, I didn't really have a need to decouple the code and the deployment.

Given that I was already hosting my code on github, the obvious solution for `CI` was github actions. I knew that I wanted to create a reusable action so that I wouldn't have to copy paste the entire flow for each new service I created. Lastly, integrating with other open source build tools, such as `docker buildx` for multi-arch image build support or `cosign` for signing, seemed to be simple as well.

Originally for `CD`, I created flows for updating a deploy repo with a new image tag, but I was never truly satisfied with it as a solution. Additionally, I chose to build the kubernetes manfiest using `kustomize` and run a `kubectl apply` afterwards to apply the new changes in my flows. `ArgoCD` eliminated all of these steps and I could self host it as well in my `k3s` cluster. Seemed like a win-win for me. 

## Github Actions

The workflow I am going to build out is avaiable on my [github repo](https://github.com/kdwils/homelab-workflow/blob/main/.github/workflows/build-push-sign.yml).

### User Inputs

When creating a workflow, users can provide inputs to the flow assuming you've defined what inputs are available.

{{< details "I need to know the image name, the registry, and a few optional fields" >}}
{{< highlight yaml >}}
name: build push sign
on:
  workflow_call:
    inputs:
      image:
        required: true
        type: string
      registry:
        required: true
        type: string
      environment:
        required: false
        type: string
        default: Homelab
      platforms:
        required: true
        type: string
        default: linux/amd64,linux/arm64,linux/arm
env:
  IMAGE_PATH: ${{ inputs.registry }}/${{ inputs.image }}
{{< /highlight >}}
{{< /details >}}

### Logging into a registry
The docker login action allows you to log into a registry for pushing an image. You can use any registry that you would like.

{{< details "I chose to use github's container registry" >}}
{{< highlight yaml >}}
- name: log in to ghcr
  uses: docker/login-action@v2
  if: github.event_name != 'pull_request'
  with:
    registry: ${{ inputs.registry }}
    username: ${{ github.REPOSITORY_OWNER }}
    password: ${{ secrets.GITHUB_TOKEN }}
{{< /highlight >}}
{{< /details >}}

### Docker

My `k3s` cluster has a mix of different architectures in it. I have an intel nuc which is `amd64`, two 4th gen raspberry pis that are `arm64`, and an older 3rd gen raspberry pi that is `armhf`. This meant that I needed to be able to build images for all three different architectures or specify a `nodeSelector` in my manifests. I chose to learn how to build imags for multiple architectures.

Docker has some cool github actions for images:

* [metadata-action](https://github.com/docker/metadata-action) generates metadata for your images such as labels or tags.
* [setup-qemu-action](https://github.com/docker/setup-qemu-action) sets up qemu for emulation.
* [setup-buildx-action](https://github.com/docker/setup-buildx-action) sets up docker buildx for building the image.
* [build-push-action](https://github.com/docker/build-push-action) can build your images and push the artifact to the registry you logged into earlier. You can also input tags and labels from the metadata-action.

{{< details "The combination of these actions is how I build my images." >}}
{{< highlight yaml >}}
- name: Docker metadata
id: meta
uses: docker/metadata-action@v4
with:
    images: |
    ${{ env.IMAGE_PATH }}
    tags: |
    type=schedule
    type=ref,event=branch
    type=ref,event=pr
    type=sha

- name: Set up QEMU
uses: docker/setup-qemu-action@v2

- name: Set up Docker Buildx
uses: docker/setup-buildx-action@v2

- name: build and publish image
id: build-and-publish
uses: docker/build-push-action@v3
with:
    context: .
    push: ${{ github.event_name != 'pull_request' }}
    platforms: ${{ inputs.platforms }}
    tags: |
    ${{ steps.meta.outputs.tags }}
    ${{ env.IMAGE_PATH }}:${{ github.SHA }}
    labels: ${{ steps.meta.outputs.labels }}
    cache-from: type=gha
    cache-to: type=gha,mode=max
{{< /highlight >}}
{{< /details >}}

### Signing
`Sigstore` offers a solution for signing artifacts called `cosign`. Check out their [github action](https://github.com/sigstore/cosign-installer#cosign-installer-github-action) for more details.

{{< details "I am signing using my github OIDC token, but you can provide your own key as well via a secret." >}}
{{< highlight yaml >}}
- name: Install Cosign
  uses: sigstore/cosign-installer@main

- name: sign
  run: cosign sign --yes ${TAGS}
  env:
    TAGS: ${{ steps.meta.outputs.tags }}
{{< /highlight >}}
{{< /details >}}


### How do I use my workflow?

You'll need to create a `.github/workflows` folder with your flow defined. Then you can point to the workflow so long as it is in a public repository.

{{< details "For example, here is the [yaml](https://github.com/kdwils/blog/blob/main/.github/workflows/ci.yaml) this blog uses to build an image." >}}
{{< highlight yaml >}}
name: Build Push Sign
on:
  push:
    branches: ["main"]
jobs:
  build-push-sign:
    uses: kdwils/homelab-workflow/.github/workflows/build-push-sign.yml@main
    secrets: inherit
    with:
      image: kdwils/blog
      registry: ghcr.io
      environment: Homelab
      platforms: linux/amd64,linux/arm64
{{< /highlight >}}
{{< /details >}}


## ArgoCD

Check out their [official docs](https://argo-cd.readthedocs.io/en/stable/operator-manual/installation/) for installation on your cluster. 

### Argo Applications

An `Application` is the definition for telling `ArgoCD` how to sync your app to your cluster.

Because `ArgoCD` is deployed in my `k3s` cluster, we can point the destination server to default kubernetes svc.

The manifests for this blog live at `https://github.com/kdwils/blog/tree/main/deploy/homelab` so I need to tell ArgoCD to look at the `/deploy/homelab` overlay.

{{< details "Heres the full Application for this blog." >}}
{{< highlight yaml >}}
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: blog
  namespace: argocd
spec:
  destination:
    namespace: blog
    server: "https://kubernetes.default.svc"
  source:
    path: deploy/homelab
    repoURL: "https://github.com/kdwils/blog"
    targetRevision: HEAD
  sources: []
  project: default
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
{{< /highlight >}}
{{< /details >}}

### Organizing Applications

I define my apps in a [separate repo](https://github.com/kdwils/homelab). This repo also contains manifests for critical infra related software for my cluster, such as `metallb`, `ingress-nginx`, or `cert-manager`. Any new apps can simply be created under the /argocd/apps [overlay](https://github.com/kdwils/homelab/tree/main/argocd/apps) and they will be automagically sync to my cluster.

For my needs, this setup works nicely as it is extremely simple to add new apps.