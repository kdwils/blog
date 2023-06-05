+++
author = "Kyle Wilson"
title = "Installing k3s and the creation of my Kubernetes cluster"
date = "2023-02-14"
description = "The creation of my a k3s Kubernetes cluster consisting of raspberry pis."
summary = "The creation of my a k3s Kubernetes cluster consisting of raspberry pis."
tags = [
    "k3s",
    "raspberry pi"
]
+++

## K3s
[K3s](https://docs.k3s.io/) is a lightweight Kubernetes distribution created by Rancher Labs, and it is fully certified by the Cloud Native Computing Foundation.

It is ideal for my setup as RPIs make up the majority of the nodes in my cluster.


### Master Node Installation
We can start the installation by checking out the [quick-start](https://docs.k3s.io/quick-start) guide.

SSH onto whatever node you want to be your master node.

First, lets create an optional configuration file for k3s to use prior to installation. 

This file should live at `/etc/rancher/k3s/config.yaml`. In my setup, I want to use my tailscale ip so the nodes will communicate via the `tailnet`. This step can be skipped if your set up differs.
```yaml
#/etc/rancher/k3s/config.yaml
node-ip: "100.72.32.68"
bind-address: "100.72.32.68"
```

Next, we can install k3s. 

For some reason, the install script did not respect disabling traefik and servicelb for my installation via the config file, so I had to do it the command. We want to disable traefik as we will be using nginx ingress controller instead. We will also be using metallb in place of servicelb.

```shell
pi@master-1:~ $ curl -sfL https://get.k3s.io | K3S_KUBECONFIG_MODE="644" INSTALL_K3S_EXEC="--disable traefik --disable servicelb" sh -s -
```

Once the k3s agent has started, we need to grab a few things to use later.

### Getting a kubeconfig
```shell
pi@master-1:~ $ sudo cat /etc/rancher/k3s/k3s.yaml
```

Lets update a few fields on the kubeconfig.

The cluster server should point to your kube api server `ip:6443`. 

If you did not set the `node-ip` in the k3s configuration you'll need to update the server ip to point to the ip address of the node in your local network. By default, this kubeconfg will use `127.0.0.1:6443` which wont work if you're not on the node.

If you did set the `node-ip` in the k3s configuration you should not have to update the sever address.

Additionally, you can change the name of the cluster to whatever you wish so you can use the context like `kubectl config use-context pi` in case you have multiple contexts.

Example of a kubeconfig using my `tailnet` ip for the raspberry pi and a cluster context of `pi`.
```yaml
apiVersion: v1
clusters:
- cluster:
    certificate-authority-data: <certificate-authority-data>
    server: https://100.72.32.68:6443
  name: pi
contexts:
- context:
    cluster: pi
    user: default
  name: pi
current-context: pi
kind: Config
preferences: {}
users:
- name: default
  user:
    client-certificate-data: <client-certificate-data>
```

### Finding your k3s join token
This is an old token and no longer in use, but the format of your token should be similar

```shell
pi@master-1:~ $ sudo cat /var/lib/rancher/k3s/server/node-token

K102fae30b4061e16a93b6dd2792f4deb7ff811bc61d52d1575c6bd4f1de890fed7::server:10b12cfbf8cabf9af720aba5d0722d26
```

### Joining Worker Nodes to the cluster

The K3s script will know you are joining a worker node when the K3S_TOKEN environment variable is present. We will need the node-token that we grabbed from our master node.

`K3S_TOKEN=K102fae30b4061e16a93b6dd2792b4deb7ff811bc61d52d1575c61drf1de890fed7::server:10b12cfbf8cabf9af720aba556722d26`

Set the K3S_URL to whatever ip address you bound your master node to with a port of 6443.
For me, this will once again be the tailscale ip.

`K3S_URL=https://100.72.32.68:6443`

```shell
pi@worker-1:~ $  curl -sfL https://get.k3s.io | K3S_URL=https://100.72.32.68:6443 K3S_TOKEN=K102fae30b4061e16a93b6dd2792f4deb7ff811bc61d52d1575c61drf1de890fed7::server:10b12cfbf8cabf9af720aba556722d26 sh -
```

You can verify your nodes are connected with the kubeconfig we got earlier.

```shell
$ kubectl get nodes
NAME       STATUS   ROLES                  AGE     VERSION
master-1   Ready    control-plane,master   26h     v1.25.6+k3s1
worker-1   Ready    <none>                 26h     v1.25.6+k3s1
```

Rinse and repeat for each node you wish to add to your cluster