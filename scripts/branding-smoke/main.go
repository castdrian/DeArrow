package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"net/http"
	"os"
	"strings"
	"time"
)

type fixture struct {
	Name              string `json:"name"`
	VideoID           string `json:"videoID"`
	Live              bool   `json:"live"`
	HTTPStatus        int    `json:"httpStatus"`
	ValidJSON         bool   `json:"validJSON"`
	ExpectedTitle     bool   `json:"expectedTitle"`
	ExpectedThumbnail bool   `json:"expectedThumbnail"`
}

func hasValidTitle(value any) bool {
	entry, ok := value.(map[string]any)
	if !ok {
		return false
	}
	if original, ok := entry["original"].(bool); ok && original {
		return false
	}
	title, ok := entry["title"].(string)
	if !ok || strings.TrimSpace(title) == "" {
		return false
	}
	if locked, ok := entry["locked"].(bool); ok && locked {
		return true
	}
	votes, ok := entry["votes"].(float64)
	return !ok || votes >= 0
}

func brandingState(root map[string]any) (bool, bool) {
	titles, _ := root["titles"].([]any)
	thumbnails, _ := root["thumbnails"].([]any)
	title := false
	for _, entry := range titles {
		if hasValidTitle(entry) {
			title = true
			break
		}
	}
	return title, len(thumbnails) > 0
}

func main() {
	fixturesPath := flag.String("fixtures", "tests/branding_fixtures.json", "")
	timeout := flag.Duration("timeout", 12*time.Second, "")
	flag.Parse()

	data, err := os.ReadFile(*fixturesPath)
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
	var fixtures []fixture
	if err := json.Unmarshal(data, &fixtures); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}

	client := &http.Client{Timeout: *timeout}
	failures := 0
	for _, test := range fixtures {
		if !test.Live {
			continue
		}
		request, err := http.NewRequest(http.MethodGet, "https://sponsor.ajay.app/api/branding?videoID="+test.VideoID, nil)
		if err != nil {
			fmt.Fprintf(os.Stderr, "FAIL %s: %v\n", test.Name, err)
			failures++
			continue
		}
		request.Header.Set("Accept", "application/json")
		request.Header.Set("User-Agent", "DeArrow")
		response, err := client.Do(request)
		if err != nil {
			fmt.Fprintf(os.Stderr, "FAIL %s: %v\n", test.Name, err)
			failures++
			continue
		}
		var root map[string]any
		decodeErr := json.NewDecoder(response.Body).Decode(&root)
		response.Body.Close()
		if response.StatusCode != test.HTTPStatus {
			fmt.Fprintf(os.Stderr, "FAIL %s: expected HTTP %d, got %d\n", test.Name, test.HTTPStatus, response.StatusCode)
			failures++
			continue
		}
		if response.StatusCode == http.StatusNotFound {
			fmt.Printf("PASS %s %s 404 no-branding\n", test.Name, test.VideoID)
			continue
		}
		if decodeErr != nil || !test.ValidJSON {
			fmt.Fprintf(os.Stderr, "FAIL %s: expected valid JSON\n", test.Name)
			failures++
			continue
		}
		title, thumbnail := brandingState(root)
		if title != test.ExpectedTitle || thumbnail != test.ExpectedThumbnail {
			fmt.Fprintf(os.Stderr, "FAIL %s: title=%t thumbnail=%t\n", test.Name, title, thumbnail)
			failures++
			continue
		}
		fmt.Printf("PASS %s %s title=%t thumbnail=%t\n", test.Name, test.VideoID, title, thumbnail)
	}
	if failures > 0 {
		os.Exit(1)
	}
}
