// rdv entrypoint wrapper for rdv-base:minimal
// Validates the rdv contract, sets up structured logging, runs the tool,
// and produces an attestation on exit.
package main

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"io/fs"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"syscall"
	"time"
)

const specVersion = "0.1"

// ── Structured logging ────────────────────────────────────────────────────────

type logEntry struct {
	Timestamp    string `json:"timestamp"`
	Level        string `json:"level"`
	Tool         string `json:"tool"`
	InvocationID string `json:"invocation_id"`
	Message      string `json:"message"`
}

func logJSON(level, tool, invocationID, msg string) {
	entry := logEntry{
		Timestamp:    time.Now().UTC().Format(time.RFC3339Nano),
		Level:        level,
		Tool:         tool,
		InvocationID: invocationID,
		Message:      msg,
	}
	b, _ := json.Marshal(entry)
	fmt.Fprintln(os.Stderr, string(b))
}

// ── Attestation ───────────────────────────────────────────────────────────────

type attestation struct {
	SpecVersion  string                        `json:"spec_version"`
	InvocationID string                        `json:"invocation_id"`
	Tool         attestationTool               `json:"tool"`
	Builder      attestationBuilder            `json:"builder"`
	Materials    map[string]string             `json:"materials"`
	Products     map[string]attestationProduct `json:"products"`
	ExitCode     int                           `json:"exit_code"`
	StartedAt    string                        `json:"started_at"`
	FinishedAt   string                        `json:"finished_at"`
	Signature    interface{}                   `json:"signature"`
}

type attestationTool struct {
	Name    string `json:"name"`
	Version string `json:"version"`
}

type attestationBuilder struct {
	ID         string `json:"id"`
	TrustLevel string `json:"trust_level"`
}

type attestationProduct struct {
	SHA256 string `json:"sha256"`
	Path   string `json:"path"`
}

func hashFile(path string) (string, error) {
	f, err := os.Open(path)
	if err != nil {
		return "", err
	}
	defer f.Close()
	h := sha256.New()
	if _, err := io.Copy(h, f); err != nil {
		return "", err
	}
	return hex.EncodeToString(h.Sum(nil)), nil
}

func hashDir(root string) (string, error) {
	type entry struct {
		rel  string
		hash string
	}
	var entries []entry

	err := filepath.WalkDir(root, func(path string, d fs.DirEntry, err error) error {
		if err != nil || d.IsDir() {
			return err
		}
		rel, _ := filepath.Rel(root, path)
		fh, err := hashFile(path)
		if err != nil {
			return err
		}
		entries = append(entries, entry{rel: rel, hash: fh})
		return nil
	})
	if err != nil {
		return "", err
	}

	sort.Slice(entries, func(i, j int) bool {
		return entries[i].rel < entries[j].rel
	})

	h := sha256.New()
	for _, e := range entries {
		fmt.Fprintf(h, "%s:%s\n", e.rel, e.hash)
	}
	return hex.EncodeToString(h.Sum(nil)), nil
}

func collectProducts(outputDir, toolName, invocationID string) map[string]attestationProduct {
	products := make(map[string]attestationProduct)
	_ = filepath.WalkDir(outputDir, func(path string, d fs.DirEntry, err error) error {
		if err != nil || d.IsDir() {
			return err
		}
		if filepath.Base(path) == ".attestation.json" {
			return nil
		}
		rel, _ := filepath.Rel(outputDir, path)
		h, err := hashFile(path)
		if err != nil {
			logJSON("warn", toolName, invocationID, fmt.Sprintf("Could not hash product %s: %v", rel, err))
			return nil
		}
		products[rel] = attestationProduct{SHA256: h, Path: path}
		return nil
	})
	return products
}

// ── Contract validation ───────────────────────────────────────────────────────

func validateContract(tool, invocationID string) error {
	required := []struct{ env, name string }{
		{"TOOL_WORKSPACE", "workspace mount"},
		{"TOOL_OUTPUT", "output mount"},
		{"TOOL_TRUST_LEVEL", "trust level"},
		{"TOOL_INVOCATION_ID", "invocation ID"},
	}
	for _, r := range required {
		if os.Getenv(r.env) == "" {
			logJSON("error", tool, invocationID, fmt.Sprintf("Contract violation: %s (%s) not set", r.env, r.name))
			return fmt.Errorf("missing required env var: %s", r.env)
		}
	}

	mounts := []struct{ env, name string }{
		{"TOOL_WORKSPACE", "workspace"},
		{"TOOL_OUTPUT", "output"},
	}
	for _, m := range mounts {
		path := os.Getenv(m.env)
		if _, err := os.Stat(path); os.IsNotExist(err) {
			logJSON("error", tool, invocationID, fmt.Sprintf("Contract violation: %s mount not found at %s", m.name, path))
			return fmt.Errorf("mount not found: %s at %s", m.name, path)
		}
	}

	outputDir := os.Getenv("TOOL_OUTPUT")
	testFile := filepath.Join(outputDir, ".rdv-write-test")
	if f, err := os.Create(testFile); err != nil {
		logJSON("error", tool, invocationID, fmt.Sprintf("Contract violation: output mount %s is not writable", outputDir))
		return fmt.Errorf("output mount not writable: %s", outputDir)
	} else {
		f.Close()
		os.Remove(testFile)
	}

	return nil
}

// ── Main ──────────────────────────────────────────────────────────────────────

func main() {
	invocationID := os.Getenv("TOOL_INVOCATION_ID")
	if invocationID == "" {
		invocationID = "unknown"
	}
	trustLevel := os.Getenv("TOOL_TRUST_LEVEL")
	if trustLevel == "" {
		trustLevel = "local"
	}

	toolName := "unknown"
	toolVersion := "unknown"
	if raw, err := os.ReadFile("/tool-manifest.json"); err == nil {
		var m map[string]interface{}
		if json.Unmarshal(raw, &m) == nil {
			if v, ok := m["name"].(string); ok {
				toolName = v
			}
			if v, ok := m["version"].(string); ok {
				toolVersion = v
			}
		}
	}

	logJSON("info", toolName, invocationID, fmt.Sprintf("rdv entrypoint starting (spec %s)", specVersion))

	if err := validateContract(toolName, invocationID); err != nil {
		logJSON("error", toolName, invocationID, "Contract validation failed: "+err.Error())
		os.Exit(2)
	}
	logJSON("info", toolName, invocationID, "Contract validated")

	startedAt := time.Now().UTC()
	workspaceHash, _ := hashDir(os.Getenv("TOOL_WORKSPACE"))

	candidates := []string{"/tool", "/tool.bin"}
	toolBin := ""
	for _, c := range candidates {
		if _, err := os.Stat(c); err == nil {
			toolBin = c
			break
		}
	}
	if toolBin == "" {
		logJSON("error", toolName, invocationID, "Tool binary not found. Expected /tool or /tool.bin")
		os.Exit(2)
	}

	args := os.Args[1:]
	cmd := exec.Command(toolBin, args...)
	cmd.Stdin = os.Stdin
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr

	exitCode := 0
	if err := cmd.Run(); err != nil {
		if exitErr, ok := err.(*exec.ExitError); ok {
			if status, ok := exitErr.Sys().(syscall.WaitStatus); ok {
				exitCode = status.ExitStatus()
			} else {
				exitCode = 1
			}
		} else {
			exitCode = 1
		}
	}

	finishedAt := time.Now().UTC()
	outputDir := os.Getenv("TOOL_OUTPUT")
	products := collectProducts(outputDir, toolName, invocationID)

	att := attestation{
		SpecVersion:  specVersion,
		InvocationID: invocationID,
		Tool: attestationTool{
			Name:    toolName,
			Version: toolVersion,
		},
		Builder: attestationBuilder{
			ID:         "rdv-" + trustLevel,
			TrustLevel: trustLevel,
		},
		Materials: map[string]string{
			"workspace": workspaceHash,
		},
		Products:   products,
		ExitCode:   exitCode,
		StartedAt:  startedAt.Format(time.RFC3339Nano),
		FinishedAt: finishedAt.Format(time.RFC3339Nano),
		Signature:  nil,
	}

	attPath := filepath.Join(outputDir, ".attestation.json")
	b, err := json.MarshalIndent(att, "", "  ")
	if err != nil {
		logJSON("error", toolName, invocationID, "Failed to marshal attestation: "+err.Error())
		os.Exit(2)
	}
	if err := os.WriteFile(attPath, b, 0644); err != nil {
		logJSON("error", toolName, invocationID, "Contract violation: failed to write attestation to "+attPath+": "+err.Error())
		os.Exit(2)
	}
	logJSON("info", toolName, invocationID, fmt.Sprintf("Attestation written to %s", attPath))

	logJSON("info", toolName, invocationID, fmt.Sprintf("Finished with exit code %d (duration: %s)",
		exitCode, finishedAt.Sub(startedAt).Round(time.Millisecond)))

	os.Exit(exitCode)
}
