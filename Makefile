all: fmt check

DEPLOY_DIR ?= manifests

IMAGE_REGISTRY ?= quay.io/rhrazdil
IMAGE_TAG ?= latest

export GOFLAGS=-mod=vendor
export GO111MODULE=on
GO_VERSION = $(shell hack/go-version.sh)

export E2E_TEST_TIMEOUT ?= 3h

BIN_DIR = $(CURDIR)/build/_output/bin/
export GOROOT=$(BIN_DIR)/go/
export GOBIN = $(GOROOT)/bin/
export PATH := $(GOBIN):$(PATH)

GO := $(GOBIN)/go

$(GO):
	hack/install-go.sh $(BIN_DIR)

fmt: whitespace goimports

goimports: $(cmd_sources) $(pkg_sources)
	$(GO) run ./vendor/golang.org/x/tools/cmd/goimports -w ./pkg ./cmd ./test/ ./tools/
	touch $@

whitespace: $(all_sources)
	./hack/whitespace.sh --fix
	touch $@

check: whitespace-check vet goimports-check
	./hack/check.sh

whitespace-check: $(all_sources)
	./hack/whitespace.sh
	touch $@

vet: $(GO) $(cmd_sources) $(pkg_sources)
	$(GO) vet ./pkg/... ./cmd/... ./test/... ./tools/...
	touch $@

goimports-check: $(GO) $(cmd_sources) $(pkg_sources)
	$(GO) run ./vendor/golang.org/x/tools/cmd/goimports -d ./pkg ./cmd
	touch $@

cluster-up:
	./cluster/up.sh

cluster-down:
	./cluster/down.sh

cluster-sync: build image-push
	./cluster/kubectl.sh create -f $(DEPLOY_DIR)/daemonset.yaml

build:
	podman build -t cidr-filtering-cni -f deploy/Dockerfile .

image-push: build
	skopeo copy containers-storage:localhost/cidr-filtering-cni docker://$(IMAGE_REGISTRY)/cidr-filtering-cni

cluster-clean:
	./cluster/clean.sh

vendor: $(GO)
	$(GO) mod tidy -compat=$(GO_VERSION)
	$(GO) mod vendor

.PHONY: \
	all \
	check \
	cluster-clean \
	cluster-down \
	cluster-sync \
	cluster-up \
	build \
	image-push \
	vendor \
