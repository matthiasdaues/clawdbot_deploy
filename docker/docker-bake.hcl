variable "REGISTRY" {
  default = "ghcr.io"
}

variable "REPOSITORY" {
  default = ""
}

variable "TAG" {
  default = "latest"
}

variable "CLAWDBOT_VERSION" {
  default = "main"
}

group "default" {
  targets = ["clawdbot"]
}

target "clawdbot" {
  context    = "docker/"
  dockerfile = "Dockerfile"
  
  args = {
    CLAWDBOT_VERSION = "${CLAWDBOT_VERSION}"
  }
  
  tags = [
    "${REGISTRY}/${REPOSITORY}:${TAG}",
    "${REGISTRY}/${REPOSITORY}:latest"
  ]
  
  platforms = ["linux/amd64"]
  
  cache-from = ["type=gha"]
  cache-to   = ["type=gha,mode=max"]
  
  output = ["type=registry"]
}

target "clawdbot-local" {
  inherits = ["clawdbot"]
  output   = ["type=docker"]
  tags     = ["clawdbot:local"]
}
