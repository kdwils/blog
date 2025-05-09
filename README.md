# blog

![sync status](https://argocd.kyledev.co/api/badge?name=blog-prod&revision=true&showAppName=true)

This repository hosts the source code and deployment configuration for the personal blog of [kdwils](https://github.com/kdwils), built with a GitOps workflow using Docker, Argo CD, and Kubernetes.

# About

This is mostly so I can keep track of the work i've done, and how to do it again in case anything happens to my cluster. This is a simple static site built using [hugo](https://github.com/gohugoio/hugo).

You can read at [blog.kyledev.co](https://blog.kyledev.co).

# Deploying
I build my blog using github actions and sync the manifests to my cluster using argocd. I expose my blog via cloudflare tunnels. You can read more about these things on the blog itself.

https://blog.kyledev.co/posts/ci-and-argocd/

https://blog.kyledev.co/posts/cloudflared-tunnel/

## Workflow Overview

### Environments

This project is deployed to two Kubernetes workloads:

Images are updated by [ArgoCD Image Updater](https://argocd-image-updater.readthedocs.io/en/stable/basics/update/)

- **Development (`dev`)** points to my internal blog.int.kyledev.co site
  - Always deploys the image tagged as `latest`.  
  - Automatically synced on every new image push to `latest`.

- **Production (`prod`)** points to my external blog.kyledev.co site
  - Deploys only images explicitly tagged with `live`.  
  - Automatically synced when a new `live` tag is pushed
