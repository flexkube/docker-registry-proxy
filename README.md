[![Build Status](https://travis-ci.org/tiangolo/docker-registry-proxy.svg?branch=master)](https://travis-ci.org/tiangolo/docker-registry-proxy)

## Supported tags and respective `Dockerfile` links

* [`latest` _(Dockerfile)_](https://github.com/tiangolo/docker-registry-proxy/blob/master/Dockerfile)

# docker-registry-proxy

Docker Registry Proxy with caching and authentication for **multiple** external Docker Registries.

## Description

This creates a Docker Registry proxy with a cache for image layers. You can configure authentication for **multiple** other Docker Registries.

Then you configure the Docker daemon in some machines to point to this Docker Registry Proxy, and they will pull their images through it.

If the other machines don't have access to external Internet, you can put this Docker Registry proxy in the middle, in a machine with Internet access, and then pull Docker images through it.

You can also use it to centralize authentication for other Docker Registries. And then the Docker installations in your other machines that use it won't need to have credentials to pull Docker images from private Docker Registries.

You configure the Docker clients once, and then all the configuration is done on the proxy. For this to work, it requires inserting a root CA certificate into the system trusted root certificates in those Docker client machines.

## Usage

* Run this Docker Registry proxy on a host close to the Docker clients.
    * It can also be the same machine, but make sure to pull and run this image before configuring the Docker client to use it as a proxy.
* Expose port `3128` to the network.
* Map volume `/docker_mirror_cache`, it will store the cached Docker images.
* Map volume `/ca`, the proxy will store the CA certificate here across restarts.

### Environment variables

You can configure it with environment variables:

* `CACHE_MAX_SIZE` (default `32g`, 32 GB): set the max size to be used for caching local Docker image layers. Use [Nginx sizes](http://nginx.org/en/docs/syntax.html).
* `REGISTRIES`: space separated list of registries to cache. You don't need to include Docker Hub, its already there.
* `AUTH_REGISTRIES`: list of `hostname:username:password` authentication info *parts*, separated by spaces.
  * `hostname`s listed here should be listed in the `REGISTRIES` environment as well, so they can be intercepted.
  * For Docker Hub authentication, `hostname` should be `auth.docker.io`, `username` should NOT be an email, use the regular username.
  * For regular registry auth (HTTP Basic), `hostname` here should be the same... unless your registry uses a different auth server. This should work for quay.io also, but I have no way to test.
  * `AUTH_REGISTRIES_DELIMITER`: to change the separator between authentication info *parts*. By default, a space: "` `". If you use keys that contain spaces (as with Google Cloud Registry), you should update this variable, e.g. setting it to `AUTH_REGISTRIES_DELIMITER=";;;"`. In that case, `AUTH_REGISTRIES` could contain something like `registry1.com:user1:pass1;;;registry2.com:user2:pass2`.
  * `AUTH_REGISTRY_DELIMITER`: to change the separator between authentication info *parts*. By default, a colon: "`:`". If you use keys that contain single colons, you should update this variable, e.g. setting it to `AUTH_REGISTRIES_DELIMITER=":::"`. In that case, `AUTH_REGISTRIES` could contain something like `registry1.com:::user1:::pass1 registry2.com:::user2:::pass2`.
  
### Google Container Registry (GCR)

For Google Container Registry (GCR), the `username` should be `_json_key` and the `password` should be the contents of the service account JSON.

Check out [GCR docs](https://cloud.google.com/container-registry/docs/advanced-authentication#json_key_file).

The service account key is in JSON format, it contains spaces ("` `") and colons ("`:`").

To be able to use GCR you should set `AUTH_REGISTRIES_DELIMITER` to something different than space (e.g. `AUTH_REGISTRIES_DELIMITER=";;;"`) and `AUTH_REGISTRY_DELIMITER` to something different than a single colon (e.g. `AUTH_REGISTRY_DELIMITER=":::"`).

### Examples

A simple example:

```bash
docker run --rm --name docker_registry_proxy -it \
       -p 0.0.0.0:3128:3128 \
       -v $(pwd)/docker_mirror_cache:/docker_mirror_cache \
       -v $(pwd)/docker_mirror_certs:/ca \
       -e REGISTRIES="k8s.gcr.io gcr.io quay.io your.own.registry another.public.registry" \
       -e AUTH_REGISTRIES="auth.docker.io:dockerhub_username:dockerhub_password your.own.registry:username:password" \
       tiangolo/docker-registry-proxy:latest
```

An example with GCR using credentials from a service account from a key file `servicekey.json`:

```bash
docker run --rm --name docker_registry_proxy -it \
       -p 0.0.0.0:3128:3128 \
       -v $(pwd)/docker_mirror_cache:/docker_mirror_cache \
       -v $(pwd)/docker_mirror_certs:/ca \
       -e REGISTRIES="k8s.gcr.io gcr.io quay.io your.own.registry another.public.registry" \
       -e AUTH_REGISTRIES_DELIMITER=";;;" \
       -e AUTH_REGISTRY_DELIMITER=":::" \
       -e AUTH_REGISTRIES="gcr.io:::_json_key:::$(cat servicekey.json);;;auth.docker.io:::dockerhub_username:::dockerhub_password" \
       tiangolo/docker-registry-proxy:latest
```

Let's say you did this on host `192.168.66.72`, you can then `curl http://192.168.66.72:3128/ca.crt` and get the proxy CA certificate.

### Configuring the Docker clients / Kubernetes nodes

On each Docker host that should use the cache:

* [Configure Docker proxy](https://docs.docker.com/config/daemon/systemd/#httphttps-proxy) pointing to the caching server.
* Add the caching server CA certificate to the list of system trusted roots.
* Restart the Docker daemon.

Do it all at once, tested on Ubuntu Xenial, which is uses SystemD:

```bash
# Add environment vars pointing Docker to use the proxy
mkdir -p /etc/systemd/system/docker.service.d
cat << EOD > /etc/systemd/system/docker.service.d/http-proxy.conf
[Service]
Environment="HTTP_PROXY=http://192.168.66.72:3128/"
Environment="HTTPS_PROXY=http://192.168.66.72:3128/"
EOD

# Get the CA certificate from the proxy and make it a trusted root.
curl http://192.168.66.72:3128/ca.crt > /usr/share/ca-certificates/docker_registry_proxy.crt
echo "docker_registry_proxy.crt" >> /etc/ca-certificates.conf
update-ca-certificates --fresh

# Reload systemd
systemctl daemon-reload

# Restart dockerd
systemctl restart docker.service
```

## Testing

Clear `dockerd` of everything not currently running: `docker system prune -a -f` *beware*.

Then do, for example, `docker pull k8s.gcr.io/kube-proxy-amd64:v1.10.4` and watch the logs on the caching proxy, it should list a lot of MISSes.

Then, clean again, and pull again. You should see HITs! Success.

Do the same for `docker pull ubuntu` and rejoice.

Test your own registry caching and authentication the same way; you don't need `docker login`, or `.docker/config.json` anymore.

## Gotchas

* If you authenticate to a private registry and pull through the proxy, those images will be served to any client that can reach the proxy, even without authentication. *beware*
 Repeat, this will make your private images very public if you're not careful.
* **Currently you cannot push images while using the proxy** which is a shame. PRs welcome.
* Setting this on Linux is relatively easy. On Mac and Windows the CA-certificate part will be very different but should work in principle.

### Why not use Docker's own registry, which has a mirror feature?

Yes, Docker offers [Registry as a pull through cache](https://docs.docker.com/registry/recipes/mirror/), *unfortunately* it only covers the DockerHub case. It won't cache images from `quay.io`, `k8s.gcr.io`, `gcr.io`, or any such, including any private registries.

This is due to the way the Docker "client" implements `--registry-mirror`, it only ever contacts mirrors for images with no repository reference (eg, from DockerHub).
When a repository is specified `dockerd` goes directly there, via HTTPS (and also via HTTP if included in a `--insecure-registry` list), thus completely ignoring the configured mirror.

### Docker itself should provide this

Yeah. Docker Inc should do it. So should NPM, Inc. Wonder why they don't. 😼

## TODO

* Allow using multiple credentials for DockerHub; this is possible since the `/token` request includes the wanted repo as a query string parameter.
* Test and make auth work with quay.io, unfortunately I don't have access to it (_hint, hint, quay_)
* Hide the mitmproxy building code under a Docker build ARG.
* I hope that in the future this can also be used as a "Developer Office" proxy, where many developers on a fast local network
  share a proxy for bandwidth and speed savings; work is ongoing in this direction.

## Note about original work

This project is based on the original work at https://github.com/rpardini/docker-registry-proxy

This version fixes some issues (e.g. support for Google Cloud Registry) and adds some features (e.g. custom cache size).
