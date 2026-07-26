# syntax=docker/dockerfile:1.7
FROM node:22-alpine AS frontend
WORKDIR /src/web
COPY web/package.json web/package-lock.json ./
RUN npm ci --ignore-scripts --no-audit --no-fund
COPY web/build.mjs ./
COPY web/src ./src
RUN npm run build

FROM golang:1.26-alpine AS test
WORKDIR /src
RUN apk add --no-cache build-base git openssh-client openssh-server shadow
COPY go.mod go.sum ./
RUN go mod download
COPY . .
COPY --from=frontend /src/web/dist ./web/dist
RUN go test -race ./... && go vet ./...

FROM test AS build
RUN CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o /out/myshell-server ./cmd/server

FROM alpine:3.23
RUN apk add --no-cache ca-certificates openssh-client tzdata \
    && addgroup -S -g 10001 myshell \
    && adduser -S -D -H -u 10001 -G myshell myshell \
    && mkdir -p /data \
    && chown myshell:myshell /data
COPY --from=build /out/myshell-server /usr/local/bin/myshell-server
USER 10001:10001
VOLUME ["/data"]
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD wget -q -T 2 -O /dev/null http://127.0.0.1:8080/health || exit 1
ENTRYPOINT ["/usr/local/bin/myshell-server"]
CMD ["serve"]
