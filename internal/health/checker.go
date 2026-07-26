package health

import (
	"context"
	"fmt"
	"net"
	"sync"
	"time"
)

type Result struct {
	ID        string    `json:"id"`
	Online    bool      `json:"online"`
	LatencyMS int64     `json:"latencyMs"`
	Error     string    `json:"error,omitempty"`
	CheckedAt time.Time `json:"checkedAt"`
}

type Target struct {
	ID   string
	Host string
	Port int
}

type Checker struct {
	timeout     time.Duration
	slots       chan struct{}
	concurrency int
	dial        func(context.Context, string, string) (net.Conn, error)
}

func New(timeout time.Duration, concurrency int) *Checker {
	dialer := net.Dialer{Timeout: timeout}
	return &Checker{
		timeout: timeout, slots: make(chan struct{}, concurrency), concurrency: concurrency,
		dial: dialer.DialContext,
	}
}

func (c *Checker) Check(ctx context.Context, target Target) Result {
	start := time.Now()
	result := Result{ID: target.ID, CheckedAt: start.UTC()}
	select {
	case c.slots <- struct{}{}:
		defer func() { <-c.slots }()
	case <-ctx.Done():
		result.Error = "check canceled"
		return result
	}
	connection, err := c.dial(ctx, "tcp", net.JoinHostPort(target.Host, fmt.Sprint(target.Port)))
	result.LatencyMS = time.Since(start).Milliseconds()
	if err != nil {
		result.Error = "unreachable"
		return result
	}
	connection.Close()
	result.Online = true
	return result
}

func (c *Checker) CheckAll(ctx context.Context, targets []Target) []Result {
	results := make([]Result, len(targets))
	if len(targets) == 0 {
		return results
	}
	type job struct {
		index  int
		target Target
	}
	jobs := make(chan job)
	var wait sync.WaitGroup
	workers := min(c.concurrency, len(targets))
	for range workers {
		wait.Add(1)
		go func() {
			defer wait.Done()
			for item := range jobs {
				results[item.index] = c.Check(ctx, item.target)
			}
		}()
	}
	for index, target := range targets {
		jobs <- job{index: index, target: target}
	}
	close(jobs)
	wait.Wait()
	return results
}
