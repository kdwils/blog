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

Probably the simplest of the zero downtime concepts - blue green deployments essentially have a `stable` and `preview` environment for testing in production. The color slots are arbitrary. Blue doesn't always mean `stable`, and green doesn't always mean `preview`. It can go either way.

When the `preview` slot is tested and ready to be promote, the promotion will result in a complete cutover of traffic to `preview` environment. The `stable` enviroment now becomes the next target for your `preview` environment.

### [Canary](https://en.wikipedia.org/wiki/Sentinel_species#Canaries_in_coal_mines) Pattern

Similar to blue-green deployments, however traffic for the new version of the service is gradually rolled out to a small subset of users instead of a complete cut over.

For example, a team may want to initally expose 0% of traffic to the `preview` environment so that initial validations can be done.

Then, as confidence grows, perhaps 10% of traffic will be routed to the `preview` environment for validations. Instead of impacting all users, only up to 10% can be impacted.

This can continue until complete confidence is achieved, and 100% of traffic is transferred to the previously `preview` environment.

## How is this achieved in kubernetes?

A generic kubernetes deployment might consist of the following:
* An ingress that points to a kubernetes service resource
* A service resource that points to a pod resource
* The pod resource where the application is actually running

Naturally, zero downtime releases are going to double the required resources for your applications for a period of time. At the minimum there will a pod that corresponds with the `stable` version of your application, and another for the new `preview` version. Each of these pods will have their own respective kubernetes service resources. There could also be ingresses, autoscalers, and any other resource tied to your `stable` version.
