+++
author = "Kyle Wilson"
title = "Envoy Proxy Bouncer Updates - v0.4.0"
date = "2025-10-27"
description = "Cloudflare Turnstile, reCAPTCHA support, custom HTML templates, JWT sessions, and metrics dashboard integration in v0.4.0"
summary = "A deep dive into the latest Envoy Proxy Bouncer release featuring CAPTCHA support, signed JWT sessions, custom templates, and dashboard metrics"
tags = [
    "envoy-proxy",
    "crowdsec",
    "bouncer"
]
+++

## It's Been a While

It has been some time since my last post on writing a CrowdSec remediation component for Envoy Proxy. While a lot of the project has changed, my goal of creating something that is easy to use, yet versatile, remains the same.

My long-term goal is to add the bouncer to the list of remediation components on the hub once I feel it is stable and safe to use.

I probably won't write a blog post on each release, but I felt this one was warranted.

## What's New

A lot of changes have been made since my last blog post - the codebase is nearly unrecognizable now. Some of the new features have been proposed by, or even written by, others using the bouncer, which brings me a lot of joy. My initial goal was to write something usable at home, but I'm happy others were able to deploy it.

A quick tl;dr of the new features:
* Support for Cloudflare Turnstile and Google reCAPTCHA for decisions that require a CAPTCHA challenge
* Support for custom HTML templates to display on ban and CAPTCHA decisions
* Support for signed JWTs for sessions when a user completes a CAPTCHA challenge successfully
* Metrics now display on the CrowdSec application dashboard for requests blocked, requests processed, and active decisions used for evaluation of requests

View the release here: https://github.com/kdwils/envoy-proxy-crowdsec-bouncer/releases/tag/v0.4.0

This was a breaking change for the bouncer, but I felt that it was justified. Previously, each pod stored the CAPTCHA sessions in-memory, which meant that pod restarts or requests load-balanced to a different pod did not know about the stored CAPTCHA sessions. The solution here was to use a signed JWT that is stored as a cookie. The other requirement with this change means that if you are protecting multiple domains with the bouncer, then you must have a bouncer per domain if you are using CAPTCHAs so that the cookies can be set properly.

In addition to my bouncer changes, CrowdSec fixed the issue regarding appending new pod IPs to the name of a bouncer in [`v1.7.1`](https://github.com/crowdsecurity/crowdsec/releases/tag/v1.7.1).

In previous versions, when a pod restarted, the new IP of the pod was appended to the previous name, resulting in names like:
`envoy-proxy-bouncer@10.42.5.250@10.42.5.4@10.42.5.49@10.42.5.64@10.42.5.76@10.42.5.80@10.42.5.85@10.42.5.165@10.42.5.238@10.42.5.37@10.42.5.127@10.42.5.45@10.42.5.172@10.42.5.2@10.42.5.8`

The bouncer works with `v1.7.1`, but I am unable to update to the latest Go package versions for the bouncer as new versions have not yet been published for [go-cs-bouncer](https://github.com/crowdsecurity/go-cs-bouncer). Once a new package version is published, I'll be sure to update the bouncer.

## What's Next

I don't have an actual roadmap planned for additional features. A lot of the wants I had for the bouncer are already present. For the most part, I'm aiming to maintain and implement features as issues are opened.

In terms of other projects, I've been interested in working with [NATS](https://www.cncf.io/projects/nats/), but haven't figured out a real use case for it yet. My current ideas revolve around an event-driven system for tracking metrics of requests made to my services, but I don't have a clear picture of how that would integrate with my homelab yet. Hopefully more to come here in a new blog post for a new project.