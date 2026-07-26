.PHONY: frontend test vet build docker-build docker-test

frontend:
	cd web && npm ci && npm run build

test:
	go test -race ./...

vet:
	go vet ./...

build:
	go build ./cmd/server

docker-build:
	docker build -t myshell:dev .

docker-test:
	docker build --target test -t myshell:test .
