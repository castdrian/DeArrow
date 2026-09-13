package tools

import (
	"encoding/json"
	"os"
	"path/filepath"
	"regexp"
	"testing"
)

type brandingFixture struct {
	Name              string `json:"name"`
	VideoID           string `json:"videoID"`
	Source            string `json:"source"`
	Surface           string `json:"surface"`
	Live              bool   `json:"live"`
	HTTPStatus        int    `json:"httpStatus"`
	ValidJSON         bool   `json:"validJSON"`
	Title             string `json:"title"`
	Original          bool   `json:"original"`
	Votes             int    `json:"votes"`
	ThumbnailCount    int    `json:"thumbnailCount"`
	Cacheable         bool   `json:"cacheable"`
	ExpectedTitle     bool   `json:"expectedTitle"`
	ExpectedThumbnail bool   `json:"expectedThumbnail"`
}

func TestBrandingFixtures(t *testing.T) {
	data, err := os.ReadFile(filepath.Join("..", "tests", "branding_fixtures.json"))
	if err != nil {
		t.Fatal(err)
	}
	var fixtures []brandingFixture
	if err := json.Unmarshal(data, &fixtures); err != nil {
		t.Fatal(err)
	}
	if len(fixtures) != 11 {
		t.Fatalf("expected eleven fixtures, got %d", len(fixtures))
	}
	validID := regexp.MustCompile(`^[A-Za-z0-9_-]{11}$`)
	seen := map[string]bool{}
	for _, fixture := range fixtures {
		if fixture.Name == "" || fixture.Source == "" || fixture.Surface == "" || !validID.MatchString(fixture.VideoID) {
			t.Fatalf("invalid fixture: %+v", fixture)
		}
		if seen[fixture.Name] {
			t.Fatalf("duplicate fixture: %s", fixture.Name)
		}
		seen[fixture.Name] = true
		validTitle := fixture.ValidJSON && fixture.HTTPStatus == 200 && !fixture.Original && fixture.Title != "" && fixture.Votes >= 0
		expectedTitle := validTitle
		expectedThumbnail := fixture.ValidJSON && fixture.HTTPStatus == 200 && fixture.ThumbnailCount > 0
		expectedCache := fixture.HTTPStatus == 404 || (fixture.ValidJSON && fixture.HTTPStatus == 200)
		if fixture.ExpectedTitle != expectedTitle || fixture.ExpectedThumbnail != expectedThumbnail || fixture.Cacheable != expectedCache {
			t.Fatalf("contract mismatch for %s", fixture.Name)
		}
		if fixture.Live && fixture.HTTPStatus == 0 {
			t.Fatalf("live fixture has no HTTP status: %s", fixture.Name)
		}
	}
	for _, name := range []string{"zoo-full", "big-buck-bunny-title-only", "penguinz0-bodycam-title", "penguinz0-tiktok-title", "penguinz0-commentary-title", "penguinz0-stream-title", "penguinz0-shorts-unlisted", "not-found", "invalid-json", "offline", "slow-timeout"} {
		if !seen[name] {
			t.Fatalf("missing fixture: %s", name)
		}
	}
	penguinz0Count := 0
	shortsCount := 0
	for _, fixture := range fixtures {
		if fixture.Source == "penguinz0" {
			penguinz0Count++
		}
		if fixture.Surface == "shorts" {
			shortsCount++
		}
	}
	if penguinz0Count < 4 || shortsCount == 0 {
		t.Fatalf("missing real feed coverage: penguinz0=%d shorts=%d", penguinz0Count, shortsCount)
	}
}
