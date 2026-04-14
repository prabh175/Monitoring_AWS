# HashiCups on Kubernetes

Deploy after Connect injection is working. Common approaches:

1. **Official tutorial manifests** from [Kubernetes get started — observability](https://developer.hashicorp.com/consul/tutorials/get-started-kubernetes/kubernetes-gs-observability) (YAML tracks current chart annotations).
2. **hashicorp-education** repos under `learn-consul-*` for version-pinned examples.

Ensure pods run in a namespace where the Connect injector is enabled (`connectInject.enabled` globally or namespace labels per chart docs). Annotations typically include:

```yaml
consul.hashicorp.com/connect-inject: "true"
```

For multi-cluster demos, register distinct service instances per DC and use prepared queries or intentions for failover stories.
