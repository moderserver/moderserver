# NGINX Gateway Fabric

Official NGINX Gateway Fabric implementation of the Kubernetes Gateway API data plane.

* **Upstream Project**: [nginx/nginx-gateway-fabric](https://github.com/nginx/nginx-gateway-fabric)
* **Version**: 2.8.1
* **Scope**: GatewayClass, the platform `Gateway` (`moderserver-gateway`) and its NGINX data plane.
* **Exposure**: the data plane publishes the Gateway on the node's ports 80 and 443 (host ports). HTTP is redirected to HTTPS; application routes attach to the `https` listener.
* **Images**: both the control plane (`Dockerfile`) and the NGINX data plane (`Dockerfile.nginx`) are built and shipped by ModerServer.
