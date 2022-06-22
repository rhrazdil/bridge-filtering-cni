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

check:
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

cluster-sync: generate
	./cluster/kubectl.sh apply -f $(DEPLOY_DIR)/daemonset.yaml

generate:
	./hack/generate.sh	
 
cluster-clean:
	./cluster/clean.sh

unit:
	TEST=true LOGFILE=/tmp/cidr-cni.log ./test-cidr-filtering-cni

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
