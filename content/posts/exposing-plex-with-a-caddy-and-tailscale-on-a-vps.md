+++
author = "Kyle Wilson"
title = "Exposing plex on a vps with tailscale's operator and caddy"
date = "2025-04-10"
description = "exposing my self-hosted plex instance on a vps with tailscale and caddy"
summary = "exposing my self-hosted plex instance on a vps with tailscale and caddy"
tags = [
    "plex",
    "kubernetes",
    "self-host,
    "caddy"
]
+++

## Prerequisites

This blog post assumes the following...
* You have an operational kuberentes cluster
* You have plex running in a kubernetes environment already
* You are using something that can expose your services outside of your cluster, such tailscale and their operator.

## My use case

I wanted to expose my plex server to friends and family, but I didn't want to port foward to a port in my home network because the public internet can be scary. I had seen a few examples of exposing internet access through a virtual private server (vps), and thought that it fit my needs.

This post is heavily inspired by Tailscale's [blog post](https://tailscale.com/blog/last-reverse-proxy-you-need), with a few tweaks to work with my setup.

I chose to go this route instead of using cloudflare tunnels due to this potentially breaching TOS, and I wanted to respect that.

Exposing services to the public internet is still a risk.. choose to do so at your own caution.


## Getting started

I ended up trying out Oracle's [free tier](https://www.oracle.com/cloud/free/) to create a vps that would act as the reverse proxy to services I wanted to expose through my cluster.

I used 