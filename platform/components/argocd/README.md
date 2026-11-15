# Argo CD

Declarative, GitOps continuous delivery and lifecycle automation for ModerServer.

* **Upstream Project**: [argoproj/argo-cd](https://github.com/argoproj/argo-cd)
* **Version**: v3.6.1
* **Scope**: Automated cluster state reconciliation and dashboard UI routed via Gateway API at `https://argocd.<domain>` (default `argocd.home.arpa`).
* **Credentials**: Nothing sensitive is stored in Git. `server.secretkey`, the initial admin password (`argocd-initial-admin-secret`) and the Redis password (`argocd-redis`) are generated on the node at first start.
* **Not deployed**: the ApplicationSet controller. The platform uses a plain app-of-apps (`platform/system`), so the extra controller would only cost memory.
