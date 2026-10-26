variable "REGISTRY" {
  default = "localhost:5005"
}

variable "VERSION" {
  default = "0.0.0-dev"
}

variable "GIT_SHA" {
  default = "unknown"
}

function "tags" {
  params = [name]
  result = ["${REGISTRY}/${name}:${VERSION}", "${REGISTRY}/${name}:${GIT_SHA}"]
}

function "cache_from" {
  params = [name]
  result = ["type=registry,ref=${REGISTRY}/cache:${name}"]
}

function "cache_to" {
  params = [name]
  result = ["type=registry,ref=${REGISTRY}/cache:${name},mode=max"]
}

group "default" {
  targets = ["api", "worker"]
}

target "_common" {
  platforms = ["linux/amd64", "linux/arm64"]
  labels = {
    "org.opencontainers.image.vendor"   = "Shop SAS"
    "org.opencontainers.image.version"  = VERSION
    "org.opencontainers.image.revision" = GIT_SHA
    "org.opencontainers.image.created"  = timestamp()
  }
  attest = [
    "type=provenance,mode=max",
    "type=sbom",
  ]
}

target "api" {
  inherits   = ["_common"]
  context    = "../../tp01-optimisation-image/starter/shopapi"
  dockerfile = "Dockerfile"
  args = {
    APP_VERSION = VERSION
    GIT_SHA     = GIT_SHA
  }
  tags       = tags("shopapi")
  cache-from = cache_from("shopapi")
  cache-to   = cache_to("shopapi")
}

target "worker" {
  inherits   = ["_common"]
  context    = "shop-worker"
  dockerfile = "Dockerfile"
  args = {
    VERSION = VERSION
    GIT_SHA = GIT_SHA
  }
  secret     = ["id=pipconf,src=shop-worker/pip.conf"]
  tags       = tags("shop-worker")
  cache-from = cache_from("shop-worker")
  cache-to   = cache_to("shop-worker")
}

target "worker-test" {
  inherits = ["worker"]
  target   = "test"
  tags     = []
  attest   = ["type=provenance,disabled=true", "type=sbom,disabled=true"]
  cache-to = []
  output   = ["type=cacheonly"]
}
