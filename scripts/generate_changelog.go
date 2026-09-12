package main

import (
	"flag"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"runtime"
	"strconv"
	"strings"
	"time"
)

type commit struct {
	hash    string
	subject string
}

var commitPattern = regexp.MustCompile(`(?i)^([a-z]+)(?:\([^)]*\))?(!)?:\s*(.+)$`)
var sectionPattern = regexp.MustCompile(`(?m)^## ([^\n]+)$`)

var groups = map[string]string{
	"feat":     "Features",
	"fix":      "Fixes",
	"perf":     "Performance",
	"refactor": "Refactoring",
	"docs":     "Documentation",
	"test":     "Tests",
	"build":    "Build",
	"ci":       "CI",
	"chore":    "Maintenance",
	"style":    "Style",
	"revert":   "Reverts",
}

var groupOrder = []string{
	"Breaking changes",
	"Features",
	"Fixes",
	"Performance",
	"Refactoring",
	"Documentation",
	"Tests",
	"Build",
	"CI",
	"Maintenance",
	"Style",
	"Reverts",
	"Other changes",
}

func rootDirectory() string {
	_, source, _, _ := runtime.Caller(0)
	return filepath.Dir(filepath.Dir(source))
}

func git(root string, arguments ...string) string {
	command := exec.Command("git", arguments...)
	command.Dir = root
	output, err := command.Output()
	if err != nil {
		return ""
	}
	return strings.TrimSpace(string(output))
}

func commitsSince(root string, tag string) []commit {
	rangeName := "HEAD"
	if tag != "" {
		rangeName = tag + "..HEAD"
	}
	output := git(root, "log", "--no-merges", "--format=%h%x09%s", rangeName)
	commits := make([]commit, 0)
	for _, line := range strings.Split(output, "\n") {
		parts := strings.SplitN(line, "\t", 2)
		if len(parts) == 2 {
			commits = append(commits, commit{hash: parts[0], subject: parts[1]})
		}
	}
	return commits
}

func releaseSection(version string, changes []commit) string {
	grouped := map[string][]string{}
	for _, change := range changes {
		group := "Other changes"
		entry := strings.TrimSpace(change.subject)
		match := commitPattern.FindStringSubmatch(change.subject)
		if match != nil {
			group = groups[strings.ToLower(match[1])]
			if group == "" {
				group = "Other changes"
			}
			entry = strings.TrimSpace(match[3])
			if match[2] != "" {
				group = "Breaking changes"
			}
		}
		grouped[group] = append(grouped[group], fmt.Sprintf("- %s (%s)", entry, change.hash))
	}
	lines := []string{"## " + version + " - " + time.Now().Format("2006-01-02"), ""}
	for _, group := range groupOrder {
		entries := grouped[group]
		if len(entries) == 0 {
			continue
		}
		lines = append(lines, "### "+group, "")
		lines = append(lines, entries...)
		lines = append(lines, "")
	}
	if len(lines) == 2 {
		lines = append(lines, "No conventional commits were found for this release.", "")
	}
	return strings.TrimSpace(strings.Join(lines, "\n"))
}

func currentSection(contents string, version string) string {
	matches := sectionPattern.FindAllStringSubmatchIndex(contents, -1)
	for index, match := range matches {
		heading := contents[match[2]:match[3]]
		if strings.SplitN(heading, " ", 2)[0] != version {
			continue
		}
		end := len(contents)
		if index+1 < len(matches) {
			end = matches[index+1][0]
		}
		return strings.TrimSpace(contents[match[0]:end])
	}
	return ""
}

func removeCurrentSection(contents string, version string) string {
	matches := sectionPattern.FindAllStringSubmatchIndex(contents, -1)
	if len(matches) == 0 {
		return contents
	}
	var result strings.Builder
	result.WriteString(contents[:matches[0][0]])
	for index, match := range matches {
		end := len(contents)
		if index+1 < len(matches) {
			end = matches[index+1][0]
		}
		heading := contents[match[2]:match[3]]
		if strings.SplitN(heading, " ", 2)[0] != version {
			result.WriteString(contents[match[0]:end])
		}
	}
	return result.String()
}

func update(root string, version string) error {
	changelogPath := filepath.Join(root, "CHANGELOG.md")
	releaseNotesPath := filepath.Join(root, ".github", "release-notes.md")
	contents := "# Changelog\n"
	if existing, err := os.ReadFile(changelogPath); err == nil {
		contents = string(existing)
	} else if !os.IsNotExist(err) {
		return err
	}
	section := currentSection(contents, version)
	if section == "" {
		section = releaseSection(version, commitsSince(root, git(root, "describe", "--tags", "--abbrev=0")))
	}
	history := strings.TrimSpace(strings.TrimPrefix(removeCurrentSection(contents, version), "# Changelog"))
	result := "# Changelog\n\n" + section
	if history != "" {
		result += "\n\n" + history
	}
	if err := os.WriteFile(changelogPath, []byte(result+"\n"), 0644); err != nil {
		return err
	}
	if err := os.WriteFile(releaseNotesPath, []byte(section+"\n"), 0644); err != nil {
		return err
	}
	headerPath := filepath.Join(root, "headers", "ChangelogData.h")
	header := "#define DEARROW_CHANGELOG @" + strconv.Quote(result+"\n") + "\n"
	return os.WriteFile(headerPath, []byte(header), 0644)
}

func main() {
	version := flag.String("version", "", "")
	flag.Parse()
	if *version == "" {
		panic("version is required")
	}
	if err := update(rootDirectory(), *version); err != nil {
		panic(err)
	}
}
