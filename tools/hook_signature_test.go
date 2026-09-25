package tools

import (
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"testing"
)

func TestHookReplacementBlocksOmitSelector(t *testing.T) {
	files, err := filepath.Glob("../sources/*.m")
	if err != nil {
		t.Fatal(err)
	}
	if len(files) == 0 {
		t.Fatal("source files not found")
	}
	blockPattern := regexp.MustCompile(`return\s+\^(id)?\s*\(([^)]*)\)`)
	selectorPattern := regexp.MustCompile(`\bSEL\b`)
	totalBlocks := 0
	for _, path := range files {
		source, err := os.ReadFile(path)
		if err != nil {
			t.Fatal(err)
		}
		blocks := blockPattern.FindAllSubmatch(source, -1)
		totalBlocks += len(blocks)
		for _, block := range blocks {
			if selectorPattern.Match(block[2]) {
				t.Errorf("%s replacement block includes SEL: %s", path, block[2])
			}
		}
	}
	if totalBlocks == 0 {
		t.Fatal("replacement blocks not found")
	}
}

func TestThumbnailSetterRestoresCachedReplacement(t *testing.T) {
	source, err := os.ReadFile("../sources/ThumbnailIntegration.m")
	if err != nil {
		t.Fatal(err)
	}
	setterSource := string(source)
	start := strings.Index(setterSource, "static BOOL InstallImageSetter")
	if start < 0 {
		t.Fatal("thumbnail setter implementation not found")
	}
	end := strings.Index(setterSource[start:], "void DeArrowInstallThumbnailIntegration")
	if end < 0 {
		t.Fatal("thumbnail setter implementation not found")
	}
	setterSource = setterSource[start : start+end]
	for _, required := range []string{
		"binding.replacementImage",
		"DeArrowInvokeImageSetterWithReplacement",
	} {
		if !strings.Contains(setterSource, required) {
			t.Errorf("thumbnail setter does not use %s", required)
		}
	}
}

func TestThumbnailVisibleStateRestoresCachedImage(t *testing.T) {
	source, err := os.ReadFile("../sources/ThumbnailIntegration.m")
	if err != nil {
		t.Fatal(err)
	}
	thumbnailSource := string(source)
	start := strings.Index(thumbnailSource, "static BOOL InstallVisibleStateHook")
	if start < 0 {
		t.Fatal("thumbnail visible-state hook not found")
	}
	end := strings.Index(thumbnailSource[start:], "void DeArrowInstallThumbnailIntegration")
	if end < 0 {
		t.Fatal("thumbnail visible-state hook boundary not found")
	}
	hookSource := thumbnailSource[start : start+end]
	for _, required := range []string{
		"didEnterVisibleState",
		"DeArrowInvokeVisibleStateWithReplacement",
		"ApplyReplacementImage",
		"ApplyThumbnailToObject",
	} {
		if !strings.Contains(hookSource, required) {
			t.Errorf("thumbnail visible-state hook does not use %s", required)
		}
	}
}
