package main

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

const sample = `---
name: golang-pro
description: "Write idiomatic Go: goroutines, channels. Use PROACTIVELY."
model: inherit
---

You are a Go expert.

## Focus
- Concurrency
`

func TestParseAgent(t *testing.T) {
	tests := []struct {
		name    string
		src     string
		want    Agent
		wantErr string
	}{
		{
			name: "quoted description with colon",
			src:  sample,
			want: Agent{
				Name:        "golang-pro",
				Description: "Write idiomatic Go: goroutines, channels. Use PROACTIVELY.",
				Model:       "inherit",
				Body:        "You are a Go expert.\n\n## Focus\n- Concurrency",
			},
		},
		{
			name: "unquoted description and crlf",
			src:  "---\r\nname: x\r\ndescription: plain text\r\nmodel: opus\r\n---\r\nbody\r\n",
			want: Agent{Name: "x", Description: "plain text", Model: "opus", Body: "body"},
		},
		{
			name: "no model key",
			src:  "---\nname: x\ndescription: d\n---\nbody\n",
			want: Agent{Name: "x", Description: "d", Body: "body"},
		},
		{name: "readme without frontmatter", src: "# Agents\n\ntext\n", wantErr: "missing frontmatter"},
		{name: "unterminated frontmatter", src: "---\nname: x\ndescription: d\nbody\n", wantErr: "unterminated frontmatter"},
		{name: "missing name", src: "---\ndescription: d\n---\nbody\n", wantErr: "no name"},
		{name: "missing description", src: "---\nname: x\n---\nbody\n", wantErr: "no description"},
		{name: "empty body", src: "---\nname: x\ndescription: d\n---\n\n", wantErr: "empty body"},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got, err := parseAgent([]byte(tt.src))
			if tt.wantErr != "" {
				if err == nil || !strings.Contains(err.Error(), tt.wantErr) {
					t.Fatalf("err = %v, want containing %q", err, tt.wantErr)
				}
				return
			}
			if err != nil {
				t.Fatalf("unexpected error: %v", err)
			}
			if got != tt.want {
				t.Errorf("got %+v\nwant %+v", got, tt.want)
			}
		})
	}
}

func TestToTOML(t *testing.T) {
	tests := []struct {
		name        string
		agent       Agent
		wantLines   []string
		absentLines []string
	}{
		{
			name:  "inherit omits model",
			agent: Agent{Name: "a", Description: "d", Model: "inherit", Body: "b"},
			wantLines: []string{
				generatedMarker,
				`name = "a"`,
				`description = "d"`,
				`sandbox_mode = "workspace-write"`,
				`developer_instructions = """`,
			},
			absentLines: []string{"model ="},
		},
		{
			name:      "explicit model is kept",
			agent:     Agent{Name: "a", Description: "d", Model: "gpt-5.5", Body: "b"},
			wantLines: []string{`model = "gpt-5.5"`},
		},
		{
			name:      "quotes and backslashes in description are escaped",
			agent:     Agent{Name: "a", Description: `say "hi" C:\dir`, Body: "b"},
			wantLines: []string{`description = "say \"hi\" C:\\dir"`},
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := toTOML(tt.agent)
			lines := strings.Split(got, "\n")
			if lines[0] != generatedMarker {
				t.Errorf("first line = %q, want marker", lines[0])
			}
			for _, w := range tt.wantLines {
				if !strings.Contains(got, w+"\n") {
					t.Errorf("missing line %q in:\n%s", w, got)
				}
			}
			for _, a := range tt.absentLines {
				if strings.Contains(got, a) {
					t.Errorf("unexpected %q in:\n%s", a, got)
				}
			}
		})
	}
}

// decodeMultiline is the inverse of tomlMultiline for the escapes it emits,
// so the round-trip proves the body survives TOML encoding intact.
func decodeMultiline(s string) string {
	s = strings.ReplaceAll(s, `""\"`, `"""`)
	return strings.ReplaceAll(s, `\\`, `\`)
}

func TestBodyRoundTrip(t *testing.T) {
	bodies := []string{
		"plain body",
		"has a backslash \\n literal and a path C:\\Users",
		`ends with quotes ""`,
		`contains """ triple quotes """ twice`,
		"tabs\tand\n\nblank lines",
	}
	for _, body := range bodies {
		out := toTOML(Agent{Name: "a", Description: "d", Body: body})
		const open = "developer_instructions = \"\"\"\n"
		i := strings.Index(out, open)
		if i < 0 {
			t.Fatalf("no developer_instructions in:\n%s", out)
		}
		enc := strings.TrimSuffix(out[i+len(open):], "\n\"\"\"\n")
		if got := decodeMultiline(enc); got != body {
			t.Errorf("round trip\n got %q\nwant %q", got, body)
		}
		if strings.Contains(enc, `"""`) {
			t.Errorf("unescaped triple quote inside multiline string: %q", enc)
		}
	}
}

func TestInstallAndUninstallDir(t *testing.T) {
	src := t.TempDir()
	out := t.TempDir()
	write := func(dir, name, content string) {
		t.Helper()
		if err := os.WriteFile(filepath.Join(dir, name), []byte(content), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	write(src, "golang-pro.md", sample)
	write(src, "architect-review.md", "---\nname: architect-reviewer\ndescription: d\nmodel: inherit\n---\nbody\n")
	write(src, "README.md", "# Agents\n\nno frontmatter\n")
	write(out, "mine.toml", "name = \"mine\"\ndescription = \"hand written\"\n")

	devnull, err := os.OpenFile(os.DevNull, os.O_WRONLY, 0)
	if err != nil {
		t.Fatal(err)
	}
	defer devnull.Close()

	if err := installDir(src, out, devnull, devnull); err != nil {
		t.Fatalf("installDir: %v", err)
	}
	// Output file is named after the frontmatter name, not the source file.
	for _, want := range []string{"golang-pro.toml", "architect-reviewer.toml", "mine.toml"} {
		if _, err := os.Stat(filepath.Join(out, want)); err != nil {
			t.Errorf("expected %s after install: %v", want, err)
		}
	}
	if _, err := os.Stat(filepath.Join(out, "README.toml")); err == nil {
		t.Error("README.md must be skipped, not converted")
	}
	got, err := os.ReadFile(filepath.Join(out, "golang-pro.toml"))
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(string(got), "You are a Go expert.") {
		t.Errorf("body missing from generated TOML:\n%s", got)
	}

	if err := uninstallDir(out, devnull); err != nil {
		t.Fatalf("uninstallDir: %v", err)
	}
	for _, gone := range []string{"golang-pro.toml", "architect-reviewer.toml"} {
		if _, err := os.Stat(filepath.Join(out, gone)); err == nil {
			t.Errorf("%s should have been removed", gone)
		}
	}
	if _, err := os.Stat(filepath.Join(out, "mine.toml")); err != nil {
		t.Error("hand-written mine.toml must survive uninstall")
	}
}

func TestInstallDirEmptySource(t *testing.T) {
	devnull, _ := os.OpenFile(os.DevNull, os.O_WRONLY, 0)
	defer devnull.Close()
	if err := installDir(t.TempDir(), t.TempDir(), devnull, devnull); err == nil {
		t.Error("expected error for a source directory with no agents")
	}
}

// TestRealAgentLibrary converts the repo's actual agents/ directory so a
// malformed agent file fails here rather than at install time.
func TestRealAgentLibrary(t *testing.T) {
	src := filepath.Join("..", "..", "agents")
	if _, err := os.Stat(src); err != nil {
		t.Skip("agents/ not found relative to the test")
	}
	out := t.TempDir()
	devnull, _ := os.OpenFile(os.DevNull, os.O_WRONLY, 0)
	defer devnull.Close()
	if err := installDir(src, out, devnull, devnull); err != nil {
		t.Fatal(err)
	}
	mds, _ := filepath.Glob(filepath.Join(src, "*.md"))
	tomls, _ := filepath.Glob(filepath.Join(out, "*.toml"))
	// Every agent except README.md converts.
	if want := len(mds) - 1; len(tomls) != want {
		t.Errorf("got %d toml files, want %d", len(tomls), want)
	}
	for _, p := range tomls {
		raw, _ := os.ReadFile(p)
		if strings.Contains(string(raw), "model =") {
			t.Errorf("%s: library agents are model: inherit and must not emit a model key", p)
		}
	}
}
