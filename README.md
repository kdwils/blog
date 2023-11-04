# blog

![sync status](https://argocd.kyledev.co/api/badge?name=blog&revision=true)

# About

This is mostly so I can keep track of the work i've done, and how to do it again in case anything happens to my cluster. This is a simple static site built using [hugo](https://github.com/gohugoio/hugo).

You can read at [blog.kyledev.co](https://blog.kyledev.co).

# Deploying
I build my blog using github actions and sync the manifests to my cluster using argocd. I expose my blog via cloudflare tunnels. You can read more about these things on the blog itself.

https://blog.kyledev.co/posts/ci-and-argocd/

https://blog.kyledev.co/posts/cloudflared-tunnel/