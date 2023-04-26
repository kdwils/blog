+++
author = "Kyle Wilson"
title = "Deploying applications to my cluster using Github Actions and ArgoCD"
date = "2023-04-25"
description = "Check out how I created a reusable github action for building, pushing, and signing docker images. ArgoCD then syncs changes to my homelab."
summary = "Check out how I created a reusable github action for building, pushing, and signing docker images. ArgoCD then syncs changes to my homelab."
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

My `k3s` cluster has a mix of different architectures in it. I have an intel nuc which is `amd64`, two 4th gen raspberry pis that are `arm64`, and an older 3rd gen raspberry pi that is `armhf`. This meant that I needed to be able to build images for all three different architectures or specify a `nodeSelector` in my manifests. I chose to learn how to build images for multiple architectures.

Docker has some cool github actions for images:

* [metadata-action](https://github.com/docker/metadata-action) generates metadata for your images such as labels or tags.
* [setup-qemu-action](https://github.com/docker/setup-qemu-action) sets up qemu for emulating operating systems.
* [setup-buildx-action](https://github.com/docker/setup-buildx-action) sets up docker buildx for building the image.
* [build-push-action](https://github.com/docker/build-push-action) can build and push your image to the registry you logged into earlier. You can also input tags and labels from the metadata-action.

{{< details "I use all of these actions in my workflow." >}}
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

You'll need to create a `.github/workflows` folder a yaml file for the flow. Then you can point to the workflow so long as it is in a public repository.

{{< details "For example, here is the [yaml](https://github.com/kdwils/blog/blob/main/.github/workflows/ci.yaml) this blog uses for CI." >}}
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

Check out the [official docs](https://argo-cd.readthedocs.io/en/stable/operator-manual/installation/) for installation on your cluster. 

### Argo Applications

An `Application` is the definition for telling `ArgoCD` how to sync an app to your cluster.

Because `ArgoCD` is deployed in my `k3s` cluster, we can point the destination server to default kubernetes svc, but you could point to a remote cluster as well.

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

I define my apps in a [separate repo](https://github.com/kdwils/homelab). This repo also contains manifests for critical infra related software for my cluster, such as `metallb`, `ingress-nginx`, or `cert-manager`. Any new apps can simply be created under the /argocd/apps [overlay](https://github.com/kdwils/homelab/tree/main/apps) and they will be automagically sync to my cluster.

For my needs, this setup works nicely as it is extremely simple to add new apps. Additionally, whenever I need to make a change I can simply push the new manifest to the homelab repo.

### ArgoCD-image-updater

Unfortunately, ArogCD wont pull image changes if you are using an image tag such as `main` or `latest` (which I am). ArgoCD-image-updater will handle pulling the latest image for your application if you configure it correctly.

This did feel like a bit of a pain to set up initially. You can see my configurations [here](https://github.com/kdwils/homelab/tree/main/argocd-image-updater) for the image-updater installation. Side note, if you're using `ghcr.io` as your registry, you need to use a personal access token as your password.

By adding these annotations for my blog `Application`, the image-updater will sync the latest image to my cluster.

{{< highlight yaml >}}
annotations:
  argocd-image-updater.argoproj.io/image-list: blog=ghcr.io/kdwils/blog
  argocd-image-updater.argoproj.io/blog.platforms: linux/arm64,linux/amd64
  argocd-image-updater.argoproj.io/blog.update-strategy: latest
{{< /highlight >}}

This seems to work pretty well, however I believe I need to configure credentials for each registry. It seems you can also have the updater commit a new image sha to your repositories as well so long as you're using `helm` or `kustomize` which would eliminte the need to constantly poll the registries.