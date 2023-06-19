# blog

## about

This is mostly so I can keep track of the work i've done, and how to do it again in case anything happens to my cluster

You can read at [blog.kyledev.co](https://blog.kyledev.co)

## deploying
I build my blog using github actions and sync the manifests to my cluster using argocd. I expose my blog via cloudflare tunnels.

https://blog.kyledev.co/posts/ci-and-argocd/

https://blog.kyledev.co/posts/cloudflared-tunnel/


![sync status](https://argocd.kyledev.co/api/badge?name=blog&revision=true)
