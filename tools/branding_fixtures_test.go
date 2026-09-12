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
	if len(fixtures) != 8 {
		t.Fatalf("expected eight fixtures, got %d", len(fixtures))
	}
	validID := regexp.MustCompile(`^[A-Za-z0-9_-]{11}$`)
	seen := map[string]bool{}
	for _, fixture := range fixtures {
		if fixture.Name == "" || !validID.MatchString(fixture.VideoID) {
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
	}
	for _, name := range []string{"full-branding", "title-only", "thumbnail-only", "no-branding", "not-found", "invalid-json", "offline", "slow-timeout"} {
		if !seen[name] {
			t.Fatalf("missing fixture: %s", name)
		}
	}
}
