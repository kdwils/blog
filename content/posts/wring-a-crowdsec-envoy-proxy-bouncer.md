+++
author = "Kyle Wilson"
title = "Writing a CrowdSec Envoy Proxy Bouncer"
date = "2025-05-30"
description = "Building a CrowdSec Bouncer for Envoy Proxy to protect Kubernetes services in my homelab."
summary = "A detailed walkthrough of implementing a CrowdSec bouncer for Envoy proxy, including code examples and deployment configuration. A tale of gRPC and Go."
tags = [
    "kubernetes",
    "crowdsec",
    "envoy-proxy",
    "envoy-gateway",
    "homelab",
    "golang",
    "go"
]
+++

# Tl;DR
For those that want to skip the reading and deploy the bouncer, here is the [source code](https://github.com/kdwils/envoy-proxy-crowdsec-bouncer). It is still a work in progress, but it is functional.

> ⚠️ **Warning**  
> This bouncer is a work in progress. Use it at your own risk.
>
> If you misconfigure this, you will likely lose connectivity through the Envoy Gateway. 
>
> To recover:
> 1. Delete the SecurityPolicy
> 2. Restart the gateway pod if needed
> 3. Verify your configuration before reapplying

It takes advantage of [crowdsec's bouncer package](https://github.com/crowdsecurity/go-cs-bouncer) and envoy proxy's [control plane package](https://github.com/envoyproxy/go-control-plane) to create a simple envoy proxy bouncer.

The bouncer works as an ext authz filter for envoy-gateway. I apply a security policy to the gateway to point it to the bouncer for all requests.

{{< details "policy.yaml" >}}
```yaml
apiVersion: gateway.envoyproxy.io/v1alpha1
kind: SecurityPolicy
metadata:
  name: envoy-bouncer-policy
  namespace: envoy-gateway-system
spec:
  targetRef:
    group: gateway.networking.k8s.io
    kind: Gateway
    name: homelab
  extAuth:
    grpc:
      backendRefs:
        - group: ""
          kind: Service
          name: envoy-bouncer
          port: 8080
          namespace: envoy-gateway-system
```
{{< /details >}}

<br>

My deployment manifest lives [here](https://github.com/kdwils/homelab/tree/main/monitoring/envoy-gateway-bouncer) if you need a reference.

I'll probably get a more detailed writeup on deploying it in the future, but for now this should be enough to get you started.

Some metrics from the envoy bouncer deployed in my cluster. Metrics are updated every 15 minutes.
```shell
╭───────────────────────────────────────────────────╮
│ Bouncer Metrics (envoy-bouncer) since 2025-05-30  │
│16:39:34 +0000                                     │
│ UTC                                               │
├────────┬─────────────────────────────────┬────────┤
│ Origin │             requests            │ unique │
│        │  bounced │  cached  │ processed │   ips  │
├────────┼──────────┼──────────┼───────────┼────────┤
│  Total │        5 │      434 │       493 │     54 │
╰────────┴──────────┴──────────┴───────────┴────────╯
````

# What is crowdsec, and what does a bouncer do?

[CrowdSec](https://www.crowdsec.net/) is a cloud-native security solution that aims to protect your infrastructure from bad actors or malicious attacks.

## Key Components

There are several components that work together:

- **LAPI** (Local API): Allows interaction with your local CrowdSec instance
- **Log Parsers**: Parse logs and feed them into scenarios
- **Scenarios**: Collections of rules evaluated against logs
- **Decisions**: Determinations on whether to ban IPs
- **Bouncers**: Components that act on decisions to allow/deny requests 

<br>

The LAPI (Local API) is a local API that allows you to interact with your local api instance. This service serves the purpose of managing your bouncers, machines, and communicating with CrowdSec remotely.

I deployed the LAPI to my cluster using their helm charts. You can see my manifests [here](https://github.com/kdwils/homelab/tree/main/monitoring/crowdsec). The installation instructions can be found [here](https://app.crowdsec.net/security-engines/setup?distribution=kubernetes).

Basically, you deploy the LAPI with an enrollment key and the approve it on the dashboard afterwards.

After this is deployed and running you can interact with the LAPI using the `cscli` on the pod.

To list your connected machines, you can run the following command. If you only have the LAPI installed you won't see anything listed here.
```shell
➜ k exec -it pods/crowdsec-lapi-6c6679c847-v2vbn -n crowdsec -- cscli machines list

───────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
 Name                  ip Address   Last Update           Status  Version                              OS                            Auth Type  Last Heartbeat 
───────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
 vps                   10.42.5.219  2025-05-30T15:50:30Z  ✔️      v1.6.8-rpm-pragmatic-arm64-f209766e  Oracle Linux Server/9.5       password   12s            
 crowdsec-agent-9sn7b  10.42.5.58   2025-05-30T15:50:00Z  ✔️      v1.6.8-f209766e-docker               Alpine Linux (docker)/3.21.3  password   42s            
 crowdsec-agent-z5k5s  10.42.4.130  2025-05-30T15:50:24Z  ✔️      v1.6.8-f209766e-docker               Alpine Linux (docker)/3.21.3  password   18s            
 crowdsec-agent-trc7g  10.42.3.23   2025-05-30T15:50:26Z  ✔️      v1.6.8-f209766e-docker               Alpine Linux (docker)/3.21.3  password   16s            
───────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
```

## Adding a machine

The VPS listed here is an oracle cloud instance. I use it as an ingress point for exposing things like Plex. Because this machine is exposed to the public internet it is a good candidate for installing crowdsec.

Again, we can visit the installation page, but this time for [linux](https://app.crowdsec.net/security-engines/setup?distribution=linux). Once installed, enroll the machine

```shell
cscli console enroll -e context <your-enrollment-key>
systemctl restart crowdsec.service
```

You should be able to see the machine once restarted
```shell
cscli machines list
```

## Bouncers

A bouncer is the component that will take action to block a request if the ip is detected as malicious. The LAPI is the source of truth for determining if an ip is malicious or not. A malicious ip will may have a state of `ban`, for example.

For the VPS, I added crowdsec's official firewall bouncer for nftables
```shell
apt install crowdsec-firewall-bouncer-nftables
```

From the pod use `cscli` add the bouncer and grab the token output. The cli should already be set up in the container.
```shell
crowdsec-lapi-6c6679c847-v2vbn:/# cscli bouncers add vps-firewall
```

Then, on the vps we need to configure the bouncer to use the token we just got from the LAPI.
```shell
nano /etc/crowdsec/bouncers/crowdsec-firewall-bouncer.yaml
```

Set the API key and the API url that points to your LAPI instance
```yaml
api_url: <your-lapi-url>
api_key: <your-api-key>
```

Finally, restart the service
```shell
systemctl restart crowdsec-firewall-bouncer.service
```

You should be able to see the bouncer in the list of bouncers
```shell
cscli bouncers list
```

Some metrics from the CrowdSec firewall bouncer
```shell
cscli metrics

╭───────────────────────────────────────────────────────────────────────────────────────────╮
│ Bouncer Metrics (vps-firewall) since 2025-05-28 16:08:13 +0000 UTC                        │
├────────────────────────────┬──────────────────┬───────────────────┬───────────────────────┤
│ Origin                     │ active_decisions │      dropped      │       processed       │
│                            │        IPs       │  bytes  │ packets │   bytes   │  packets  │
├────────────────────────────┼──────────────────┼─────────┼─────────┼───────────┼───────────┤
│ CAPI (community blocklist) │           23.71k │ 134.33k │   2.50k │         - │         - │
│ crowdsec (security engine) │                0 │  87.40k │   1.38k │         - │         - │
├────────────────────────────┼──────────────────┼─────────┼─────────┼───────────┼───────────┤
│                      Total │           23.71k │ 221.73k │   3.88k │     2.53G │     1.73M │
╰────────────────────────────┴──────────────────┴─────────┴─────────┴───────────┴───────────╯
```

# Writing a CrowdSec Envoy Proxy Bouncer

I didn't see anything available for adding a bouncer to envoy proxy, and I thought this would be a fun project to take on, so here we are.

Our bouncer needs to know how to extract the actual client ip from an incoming request, and then query the LAPI to see if the ip is banned or not. If it is, we need to deny the request by returning a forbidden status.

Envoy already has a [go control plane](https://github.com/envoyproxy/go-control-plane) written, we can reference it in our bouncer for the gRPC calls between envoy-proxy and our service.

To start, we need to set up a gRPC server that will handle the requests from Envoy that implements the [envoy_authz.CheckRequest](https://github.com/envoyproxy/go-control-plane/tree/main/envoy/service/auth/v3) service.

Here's a graceful implementation of the server:
{{< details "server.go" >}}
```go
package server

import (
	"context"
	"fmt"
	"log/slog"
	"net"

	auth "github.com/envoyproxy/go-control-plane/envoy/service/auth/v3"
	envoy_type "github.com/envoyproxy/go-control-plane/envoy/type/v3"
	"github.com/kdwils/envoy-proxy-bouncer/bouncer"
	"github.com/kdwils/envoy-proxy-bouncer/config"
	"github.com/kdwils/envoy-proxy-bouncer/logger"
	"google.golang.org/genproto/googleapis/rpc/status"
	"google.golang.org/grpc"
	"google.golang.org/grpc/reflection"
)

type Server struct {
	auth.UnimplementedAuthorizationServer
	bouncer bouncer.Bouncer
	config  config.Config
	logger  *slog.Logger
}

func NewServer(config config.Config, bouncer bouncer.Bouncer, logger *slog.Logger) *Server {
	return &Server{
		config:  config,
		bouncer: bouncer,
		logger:  logger,
	}
}

func (s *Server) Serve(ctx context.Context, port int) error {
	lis, err := net.Listen("tcp", fmt.Sprintf(":%d", port))
	if err != nil {
		return fmt.Errorf("failed to listen: %v", err)
	}

	grpcServer := grpc.NewServer(
		grpc.UnaryInterceptor(s.loggerInterceptor),
	)
	auth.RegisterAuthorizationServer(grpcServer, s)
	reflection.Register(grpcServer)

	go func() {
		<-ctx.Done()
		s.logger.Info("shutting down gRPC server...")
		grpcServer.GracefulStop()
		s.logger.Info("gRPC server shutdown complete")
	}()

	return grpcServer.Serve(lis)
}
```
{{< /details >}}

Next the server needs to implement the `CheckRequest` method

```go
func (s *Server) Check(ctx context.Context, req *auth.CheckRequest) (*auth.CheckResponse, error) {
  return nil, nil
}
```

The request struct looks like this
```go
type CheckRequest struct {
    state         protoimpl.MessageState
    sizeCache     protoimpl.SizeCache
    unknownFields protoimpl.UnknownFields

    // The request attributes.
    Attributes *AttributeContext `protobuf:"bytes,1,opt,name=attributes,proto3" json:"attributes,omitempty"`
}
```

We can extract the socket ip and the request headers from the request attributes
```go
ip := ""
if req.Attributes != nil && req.Attributes.Source != nil && req.Attributes.Source.Address != nil {
  if socketAddress := req.Attributes.Source.Address.GetSocketAddress(); socketAddress != nil {
    ip = socketAddress.GetAddress()
  }
}

headers := make(map[string]string)
if req.Attributes != nil && req.Attributes.Request != nil && req.Attributes.Request.Http != nil {
  headers = req.Attributes.Request.Http.Headers
}
```

This should be sufficient enough to get us started to determine who is making the request. We will be making use for the `x-forwarded-for` header to determine the client ip if we can.

Next, we need to implement the logic to determine if the ip is banned or not. This is where the LAPI comes in.

I house the requirements for this in a bouncer struct
```go
import (
	"net"

	csbouncer "github.com/crowdsecurity/go-cs-bouncer"
	"github.com/kdwils/envoy-proxy-bouncer/cache"
)

type EnvoyBouncer struct {
	stream          *csbouncer.StreamBouncer
	trustedProxies  []*net.IPNet
	cache           *cache.Cache
	mu              *sync.RWMutex
}
```
<br>

The StreamBouncer creates a long running connection to the LAPI that will be streamed updates from the LAPI on new ips being added/removed from the ban list. The job of the stream client is to populate th cache with decisions for ip addresses. It will live in a go routine later.

<br>

First, we need to implement a cache to store the decisions we get from the LAPI. We create a simple in-memory cache to store the results of the LAPI calls that is go-routine safe.

{{< details "cache.go" >}}
```go
package cache

import (
	"sync"

	"github.com/crowdsecurity/crowdsec/pkg/models"
)

type Cache struct {
	entries map[string]models.Decision
	mu      sync.RWMutex
}

func New() *Cache {
	return &Cache{
		mu:      sync.RWMutex{},
		entries: make(map[string]models.Decision),
	}
}

func (c *Cache) Set(ip string, d models.Decision) {
	c.mu.Lock()
	defer c.mu.Unlock()

	c.entries[ip] = d
}

func (c *Cache) Delete(ip string) {
	c.mu.Lock()
	defer c.mu.Unlock()
	delete(c.entries, ip)
}

func (c *Cache) Get(ip string) (models.Decision, bool) {
	c.mu.RLock()
	defer c.mu.RUnlock()
	entry, ok := c.entries[ip]
	return entry, ok
}

func (c *Cache) Size() int {
	c.mu.RLock()
	defer c.mu.RUnlock()
	return len(c.entries)
}
```

Next, we need to implement the a go routine that will sync the cache with the LAPI. This is where the StreamBouncer comes in.

We get updates for an ip address when a new decision is added or an old decision is deleted.

{{< details "sync.go" >}}
```go
func (b *EnvoyBouncer) Sync(ctx context.Context) error {
	if b.stream == nil {
		return errors.New("stream not initialized")
	}

	logger := logger.FromContext(ctx).With(slog.String("method", "sync"))
	go func() {
		b.stream.Run(ctx)
	}()

	for {
		select {
		case <-ctx.Done():
			logger.Debug("sync context done")
			return nil
		case d := <-b.stream.Stream:
			if d == nil {
				logger.Debug("received nil decision stream")
				continue
			}

			for _, decision := range d.Deleted {
				if decision == nil || decision.Value == nil {
					continue
				}
				logger.Debug("deleting decision", "decision", decision)
				b.cache.Delete(*decision.Value)
			}

			for _, decision := range d.New {
				if decision == nil || decision.Value == nil {
					continue
				}
				logger.Debug("received new decision", "decision", decision)
				b.cache.Set(*decision.Value, *decision)
			}
		}
	}
}
```
{{< /details >}}

Then, we need to implement the logic to determine if the ip is banned or not.

Our bouncer needs to know the following to function properly:
- The source ip of the request
- The headers of the request

So, our method receiver then looks like
```go
func (b *EnvoyBouncer) Bounce(ctx context.Context, ip string, headers map[string]string) (bool, error)
```

The boolean returned tells us whether to bounce the request or not.

The first thing we need to do is determine the actual client ip making the request. We need to respect the `x-forwarded-for` header if it exists. We also need a way for users to specify trusted proxies that are allowed to bypass the bouncer. These ips that are trusted are skipped when determining the client ip.
{{< details "partial-bouncer.go" >}}
```go
func (b *EnvoyBouncer) Bounce(ctx context.Context, ip string, headers map[string]string) (bool, error) {
	var xff string
	for k, v := range headers {
		if strings.EqualFold(k, "x-forwarded-for") {
			xff = v
			break
		}
	}
	if xff != "" {
		if len(xff) > maxHeaderLength {
			return false, errors.New("header too big")
		}
		ips := strings.Split(xff, ",")
		if len(ips) > maxIPs {
			return false, errors.New("too many ips in chain")
		}

		for i := len(ips) - 1; i >= 0; i-- {
			parsedIP := strings.TrimSpace(ips[i])
			if !b.isTrustedProxy(parsedIP) && isValidIP(parsedIP) {
				ip = parsedIP
				break
			}
		}
	}
}

func (b *EnvoyBouncer) isTrustedProxy(ip string) bool {
	parsed := net.ParseIP(ip)
	if parsed == nil {
		return false
	}
	for _, ipNet := range b.trustedProxies {
		if ipNet.Contains(parsed) {
			return true
		}
	}
	return false
}
```
{{< /details >}}

We traverse the list of ips from right to left, and check if the ip is in one of the trusted proxies cidr range. If not, we need to check if the ip is valid.

The rest of the bouncer logic is pretty straightforward. We check if the ip is in the cache, and if it is, we return the cached result. Otherwise, we can assume the ip is not banned and may continue on.

{{< details "bouncer.go" >}}
```go
func (b *EnvoyBouncer) Bounce(ctx context.Context, ip string, headers map[string]string) (bool, error){
	if ip == "" {
		return false, errors.New("no ip found")
	}

	if b.cache == nil {
		return false, errors.New("cache is nil")
	}

	var xff string
	for k, v := range headers {
		if strings.EqualFold(k, "x-forwarded-for") {
			xff = v
			break
		}
	}
	if xff != "" {
		if len(xff) > maxHeaderLength {
			return false, errors.New("header too big")
		}
		ips := strings.Split(xff, ",")
		if len(ips) > maxIPs {
			return false, errors.New("too many ips in chain")
		}
		for i := len(ips) - 1; i >= 0; i-- {
			parsedIP := strings.TrimSpace(ips[i])
			if !b.isTrustedProxy(parsedIP) && isValidIP(parsedIP) {
				ip = parsedIP
				break
			}
		}
	}

	if !isValidIP(ip) {
		return false, errors.New("invalid ip address")
	}

	decision, ok := b.cache.Get(ip)
	if !ok {
		return true, nil
	}
	if IsBannedDecision(&decision) {
		return true, nil
	}
	return false, nil
}

func IsBannedDecision(decision *models.Decision) bool {
	if decision == nil || decision.Type == nil {
		return false
	}
	return strings.EqualFold(*decision.Type, "ban")
}
```
{{< /details >}}

The bouncer uses cobra to create a CLI and viper to manage configurations. Here is the command that ties it all together and serves the grpc api.

{{< details "serve.go" >}}
```go
// serveCmd represents the serve command
var serveCmd = &cobra.Command{
	Use:   "serve",
	Short: "serve the envoy gateway bouncer",
	Long:  `serve the envoy gateway bouncer`,
	RunE: func(cmd *cobra.Command, args []string) error {
		v := viper.GetViper()
		config, err := config.New(v)
		if err != nil {
			return err
		}

		level := logger.LevelFromString(config.Server.LogLevel)

		handler := slog.NewJSONHandler(os.Stdout, &slog.HandlerOptions{Level: level})
		logger := slog.New(handler)

		logger.Info("starting envoy-proxy-bouncer", "version", version.Version, "logLevel", level)

		cache := cache.New(config.Cache.Ttl, config.Cache.MaxEntries)
		go cache.Cleanup() // clean up expired entries in the background

		bouncer, err := bouncer.NewEnvoyBouncer(config.Bouncer.ApiKey, config.Bouncer.ApiURL, config.Bouncer.TrustedProxies, cache)
		if err != nil {
			return err
		}
		go bouncer.Sync(context.Background()) // sync from the lapi in the background

		ctx, cancel := context.WithCancel(context.Background())
		server := server.NewServer(config, bouncer, logger)
		sigCh := make(chan os.Signal, 1)
		signal.Notify(sigCh, syscall.SIGINT, syscall.SIGTERM)
		go func() {
			sig := <-sigCh
			logger.Info("received signal", "signal", sig)
			cancel()
		}()

		err = server.Serve(ctx, config.Server.Port)
		return err
	},
}
```

To start the server
```shell
go run main.go serve
```

{{< /details >}}

# Deploying the bouncer
I deployed the bouncer to my home kubernetes cluster. The manifest consists of a deployment, a service, and a configmap + secret to configure the bouncer. The full manifest is [here](https://github.com/kdwils/homelab/tree/main/monitoring/envoy-gateway-bouncer).

We need to tell the envoy-gateway to use grpc for the ext authz, and to talk to the bouncer service on port 8080. Both the service port and the container port are set to 8080 in my case.

{{< details "policy.yaml" >}}
```yaml
apiVersion: gateway.envoyproxy.io/v1alpha1
kind: SecurityPolicy
metadata:
  name: envoy-bouncer-policy
  namespace: envoy-gateway-system
spec:
  targetRef:
    group: gateway.networking.k8s.io
    kind: Gateway
    name: homelab
  extAuth:
    grpc:
      backendRefs:
        - group: ""
          kind: Service
          name: envoy-bouncer
          port: 8080
          namespace: envoy-gateway-system
```
{{< /details >}}

# Closing Thoughts

While CrowdSec is a dope open source project, there were some awkward aspects to the ecosystem that I encountered. This could be due to my lack of understanding of how the package is intended to be used so take these with a grain of salt.

#### Ephemeral Challenges
- [Bouncers register as new instances on pod restarts](https://github.com/crowdsecurity/crowdsec/issues/3663).
- Agents register as new machines on pod restarts.

I think this happens as its "registering" as a new instance of the bouncer each time, and runs into naming conflicts.

#### GO SDK Improvements
- Better documentation for metrics integration
- More streamlined metrics exposure

I am hoping to contribute to the ecosystem to improve the experience for others, and I definitely intend to keep using it in my homelab.