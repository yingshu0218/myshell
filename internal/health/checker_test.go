package health

import (
	"context"
	"net"
	"strconv"
	"sync/atomic"
	"testing"
	"time"
)

func TestCheckReachableTarget(t *testing.T) {
	listener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	defer listener.Close()
	host, portText, _ := net.SplitHostPort(listener.Addr().String())
	port, _ := strconv.Atoi(portText)
	checker := New(time.Second, 1)
	result := checker.Check(context.Background(), Target{ID: "local", Host: host, Port: port})
	if !result.Online || result.Error != "" {
		t.Fatalf("result = %+v", result)
	}
}

func TestCheckCanceled(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	checker := New(time.Second, 1)
	result := checker.Check(ctx, Target{ID: "canceled", Host: "192.0.2.1", Port: 22})
	if result.Online {
		t.Fatal("canceled check reported online")
	}
}

func TestCheckAllBoundsConcurrency(t *testing.T) {
	var active atomic.Int32
	var maximum atomic.Int32
	targets := make([]Target, 20)
	for index := range targets {
		targets[index] = Target{ID: strconv.Itoa(index), Host: "example.test", Port: 22}
	}
	checker := New(time.Second, 2)
	checker.dial = func(ctx context.Context, network, address string) (net.Conn, error) {
		current := active.Add(1)
		defer active.Add(-1)
		for {
			seen := maximum.Load()
			if current <= seen || maximum.CompareAndSwap(seen, current) {
				break
			}
		}
		time.Sleep(10 * time.Millisecond)
		client, server := net.Pipe()
		go server.Close()
		return client, nil
	}
	results := checker.CheckAll(context.Background(), targets)
	if len(results) != len(targets) {
		t.Fatalf("result count = %d", len(results))
	}
	if maximum.Load() > 2 {
		t.Fatalf("maximum concurrency = %d, want <= 2", maximum.Load())
	}
}
