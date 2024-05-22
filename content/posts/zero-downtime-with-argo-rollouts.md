+++
author = "Kyle Wilson"
title = "Zero downtime releases with argo rollouts"
date = "2024-05-20"
description = "The pros, and cons, of argo rollouts for zero downtime releases"
summary = "The pros, and cons, of argo rollouts for zero downtime releases"
tags = [
    "argocd",
    "argo rollouts",
    "blue-green",
    "canary",
    "zero downtime release"
]
+++

## Zero downtime releases - What and why?

Zero downtime releases aimed at updating services without causing any downtime for users in a production (or additionally lower) environment(s). The end goal here is to reduce opportunity for surpises when deploying to a new environment where user experiences can be impacted.

For the purposes of this post, I will be focusing on only two patterns: Blue-Green and Canary deployments.

### Blue-Green Pattern

Probably the simplest of the zero downtime concepts - blue green deployments essentially have a `live` and `idle` environment for testing in production. The color slots are arbitrary. Blue doesn't always mean `live`, and green doesn't always mean `idle`. It can go either way.

When the `idle` slot is tested and ready to be promote, the promotion will result in a complete cutover of traffic to `idle` environment. The `live` enviroment now becomes `idle`, and visa versa.

### [Canary](https://en.wikipedia.org/wiki/Sentinel_species#Canaries_in_coal_mines) Pattern

Similar to blue-green deployments, however traffic for the new version of the service is gradually rolled out to a small subset of users instead of a complete cut over.

For example, a team may want to initally expose 0% of traffic to the `idle` environment so that initial validations can be done.

Then, as confidence grows, perhaps 10% of traffic will be routed to the `idle` environment for validations. Instead of impacting all users, only up to 10% can be impacted.

This can continue until complete confidence is achieved, and 100% of traffic is transferred to the previously `idle` environment.

## How is this achieved in kubernetes?

A generic kubernetes deployment might consist of the following:
* An ingress that points to a kubernetes service resource
* A service resource that points to a pod resource
* The pod resource where the application is running
