+++
author = "Kyle Wilson"
title = "Tailscale on RPIs"
date = "2023-02-15"
description = "Tailscale on RPIs"
summary = "Installing tailscale on my machines to make them accessible from anywhere in the world."
tags = [
    "tailscale"
]
+++

# Tailscale on RPIs
In my home kubernetes cluster, I have 4 raspberry PIs and an intel nuc. I want to be able to communicate with my cluster and nodes when I am not home. Tailscale seemed like an easy solution to my problem. Additionally, its pretty simple to share my tailnet with friends + family.

## Tailscale

[Tailscale](https://tailscale.com/kb/1151/what-is-tailscale/) is a VPN service that makes the devices and applications you own accessible anywhere in the world. Tailscale will create a virtual private network for you, aka the `tailnet`, where you can safely route to your devices.

### Sign up

Check out the [install](https://tailscale.com/kb/1017/install/) page for tailscale and create an account.

### Installation
Each node in our cluster will need to have tailscale installed. You can do so by heading over to the stable [releases](https://pkgs.tailscale.com/stable/) page and follow instructions for your operating system.

{{< highlight bash >}}curl -fsSL https://pkgs.tailscale.com/stable/raspbian/bullseye.noarmor.gpg | sudo tee /usr/share/keyrings/tailscale-archive-keyring.gpg >/dev/null
curl -fsSL https://pkgs.tailscale.com/stable/raspbian/bullseye.tailscale-keyring.list | sudo tee /etc/apt/sources.list.d/tailscale.list

sudo apt-get update && sudo apt-get install tailscale
sudo tailscale up{{< /highlight >}}
> **_NOTE:_**  You'll need to authenticate against the link printed to the terminal if this is your first time adding a specific machine to your tailnet.

You should then be able to see your machine on the [admin console](https://login.tailscale.com/admin/machines).
![master-1 node connected](/images/installing-tailscale/tailscale-machine.png)

Success!

### Using the tailnet

Any machine you have connected to your tailnet can talk to any other machine that is also connected.

I have the tailscale app installed on my laptop, so I am able to reach our newly added tailscale machine.


From my laptop to the raspberry pi node with the tailscale app running on my laptop
{{< highlight bash >}}
$ ping 100.72.32.68
PING 100.72.32.68 (100.72.32.68): 56 data bytes
64 bytes from 100.72.32.68: icmp_seq=0 ttl=64 time=8.961 ms
64 bytes from 100.72.32.68: icmp_seq=1 ttl=64 time=6.908 ms
64 bytes from 100.72.32.68: icmp_seq=2 ttl=64 time=7.181 ms
^C
--- 100.72.32.68 ping statistics ---
3 packets transmitted, 3 packets received, 0.0% packet loss
round-trip min/avg/max/stddev = 6.908/7.683/8.961/0.910 ms
{{< /highlight >}}

From my raspberry pi to my laptop
{{< highlight bash >}}
pi@master-1:~ $ ping 100.127.244.60
PING 100.127.244.60 (100.127.244.60) 56(84) bytes of data.
64 bytes from 100.127.244.60: icmp_seq=1 ttl=64 time=8.39 ms
64 bytes from 100.127.244.60: icmp_seq=2 ttl=64 time=6.11 ms
64 bytes from 100.127.244.60: icmp_seq=3 ttl=64 time=6.74 ms
^C
--- 100.127.244.60 ping statistics ---
3 packets transmitted, 3 received, 0% packet loss, time 2003ms
rtt min/avg/max/mdev = 6.112/7.080/8.386/0.958 ms
{{< /highlight >}}


### MagicDNS
[MagicDNS](https://tailscale.com/kb/1081/magicdns/) is a tailscale feature that automatically registers DNS names for devices in your network.

This has a multitude of uses, but I mainly take advantage of the host names for ssh purposes. Remembering host names is a lot easier than memorizing ip addresses.

{{< highlight bash >}}
$ ssh pi@master-1
{{< /highlight >}}

vs

{{< highlight bash >}}
$ ssh pi@100.72.32.68
{{< /highlight >}}


# Whats Next?

Check out how to [install k3s](/posts/k3s-kubernetes-cluster/) and create a kubernetes cluster that talks through our tailnet.