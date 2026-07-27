TAILSCALE_GO_ENV += GOARCH=mipsle CGO_ENABLED=0

$(eval $(generic-package))
