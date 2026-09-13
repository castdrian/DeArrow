package tools

import (
	"encoding/json"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"testing"
)

type metadataFixture struct {
	Name    string `json:"name"`
	Adapter string `json:"adapter"`
	VideoID string `json:"videoID"`
	Title   string `json:"title"`
	Channel string `json:"channel"`
}

func TestMetadataFixtures(t *testing.T) {
	data, err := os.ReadFile(filepath.Join("..", "tests", "metadata_fixtures.json"))
	if err != nil {
		t.Fatal(err)
	}
	var fixtures []metadataFixture
	if err := json.Unmarshal(data, &fixtures); err != nil {
		t.Fatal(err)
	}
	if len(fixtures) != 5 {
		t.Fatalf("expected five fixtures, got %d", len(fixtures))
	}
	validID := regexp.MustCompile(`^[A-Za-z0-9_-]{11}$`)
	seen := map[string]bool{}
	for _, fixture := range fixtures {
		if fixture.Name == "" || fixture.Adapter == "" || !validID.MatchString(fixture.VideoID) {
			t.Fatalf("invalid fixture: %+v", fixture)
		}
		if seen[fixture.Adapter] {
			t.Fatalf("duplicate adapter fixture: %s", fixture.Adapter)
		}
		seen[fixture.Adapter] = true
	}
	for _, adapter := range []string{"YTVideoNode", "YTVideoWithContextNode", "Elements", "Shorts", "Incomplete"} {
		if !seen[adapter] {
			t.Fatalf("missing adapter fixture: %s", adapter)
		}
	}
	if fixtures[len(fixtures)-1].Title != "" || fixtures[len(fixtures)-1].Channel != "" {
		t.Fatal("incomplete renderer fixture must have no optional metadata")
	}
}

func TestMetadataClassifierContract(t *testing.T) {
	source, err := os.ReadFile(filepath.Join("..", "sources", "Metadata.m"))
	if err != nil {
		t.Fatal(err)
	}
	contents := string(source)
	for _, required := range []string{
		"NodeHasKnownClass",
		"YTVideoWithContextNode",
		"YTShortsNode",
		"ELMCellNode",
		"return nil;",
	} {
		if !strings.Contains(contents, required) {
			t.Fatalf("metadata classifier is missing %s", required)
		}
	}
	for _, forbidden := range []string{
		"containsString:@\"short\"",
		"containsString:@\"reel\"",
		"return [self recordForObject:node];",
	} {
		if strings.Contains(contents, forbidden) {
			t.Fatalf("metadata classifier still has broad fallback %s", forbidden)
		}
	}
}
