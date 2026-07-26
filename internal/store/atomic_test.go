package store

import (
	"os"
	"path/filepath"
	"testing"
)

func TestWriteAndReadJSON(t *testing.T) {
	t.Parallel()
	path := filepath.Join(t.TempDir(), "state.json")
	input := struct {
		Value string `json:"value"`
	}{Value: "saved"}
	if err := WriteJSON(path, input, 0o600); err != nil {
		t.Fatal(err)
	}
	var output struct {
		Value string `json:"value"`
	}
	if err := ReadJSON(path, &output); err != nil {
		t.Fatal(err)
	}
	if output.Value != input.Value {
		t.Fatalf("got %q, want %q", output.Value, input.Value)
	}
	info, err := os.Stat(path)
	if err != nil {
		t.Fatal(err)
	}
	if info.Mode().Perm() != 0o600 {
		t.Fatalf("mode is %o, want 600", info.Mode().Perm())
	}
}
