package main

import (
	"encoding/json"
	"errors"
	"fmt"
	"image"
	_ "image/png"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"runtime"
	"strconv"
	"strings"
	"time"
)

const defaultDeviceID = "00008030-001624583AF9402E"
const youtubeBundleID = "com.google.ios.youtube"

func repositoryRoot() (string, error) {
	if value := os.Getenv("DEARROW_ROOT"); value != "" {
		return filepath.Abs(value)
	}
	_, source, _, ok := runtime.Caller(0)
	if ok {
		root := filepath.Dir(filepath.Dir(filepath.Dir(source)))
		if _, err := os.Stat(filepath.Join(root, "control")); err == nil {
			return root, nil
		}
	}
	root, err := os.Getwd()
	if err != nil {
		return "", err
	}
	for {
		if _, err := os.Stat(filepath.Join(root, "control")); err == nil {
			return root, nil
		}
		parent := filepath.Dir(root)
		if parent == root {
			return "", errors.New("could not locate DeArrow repository root")
		}
		root = parent
	}
}

func commandPath(environmentName, commandName string) string {
	if value := os.Getenv(environmentName); value != "" {
		return value
	}
	if value, err := exec.LookPath(commandName); err == nil {
		return value
	}
	return commandName
}

func run(directory, name string, args ...string) ([]byte, error) {
	command := exec.Command(name, args...)
	command.Dir = directory
	return command.CombinedOutput()
}

func runToFile(directory, outputPath, name string, args ...string) error {
	if err := os.MkdirAll(filepath.Dir(outputPath), 0755); err != nil {
		return err
	}
	file, err := os.Create(outputPath)
	if err != nil {
		return err
	}
	defer file.Close()
	command := exec.Command(name, args...)
	command.Dir = directory
	command.Stdout = file
	command.Stderr = file
	return command.Run()
}

func runWithEnvironment(directory string, environment []string, name string, args ...string) ([]byte, error) {
	command := exec.Command(name, args...)
	command.Dir = directory
	command.Env = append(os.Environ(), environment...)
	return command.CombinedOutput()
}

func writeText(path, value string) error {
	if err := os.MkdirAll(filepath.Dir(path), 0755); err != nil {
		return err
	}
	return os.WriteFile(path, []byte(value), 0644)
}

func outputDirectory(root, requested, prefix string) (string, error) {
	if requested != "" {
		if err := os.MkdirAll(requested, 0755); err != nil {
			return "", err
		}
		return requested, nil
	}
	directory := filepath.Join(root, "test-artifacts", prefix+time.Now().UTC().Format("20060102T150405Z"))
	if err := os.MkdirAll(directory, 0755); err != nil {
		return "", err
	}
	return directory, nil
}

func jbP1lotPath() string {
	return commandPath("JB_P1LOT_BIN", "jb-p1lot")
}

func jbP1lotToFile(outputPath, device, action string, args ...string) error {
	allArgs := []string{action, "--json", "--device", device}
	allArgs = append(allArgs, args...)
	return runToFile("", outputPath, jbP1lotPath(), allArgs...)
}

func jbP1lotShell(outputPath, device, command string) error {
	return jbP1lotToFile(outputPath, device, "shell_exec", "--command", command)
}

func parseToolOutput(path string) string {
	contents, err := os.ReadFile(path)
	if err != nil {
		return ""
	}
	var value any
	if json.Unmarshal(contents, &value) != nil {
		return string(contents)
	}
	var find func(any) string
	find = func(current any) string {
		switch typed := current.(type) {
		case map[string]any:
			if value, ok := typed["output"].(string); ok {
				return value
			}
			if value, ok := typed["data"].(string); ok {
				return value
			}
			for _, child := range typed {
				if value := find(child); value != "" {
					return value
				}
			}
		case []any:
			for _, child := range typed {
				if value := find(child); value != "" {
					return value
				}
			}
		}
		return ""
	}
	return find(value)
}

func deviceIdentifier(args []string) string {
	if value := os.Getenv("DEARROW_DEVICE_ID"); value != "" {
		return value
	}
	if len(args) > 0 && args[0] != "" {
		return args[0]
	}
	return defaultDeviceID
}

func captureDevice(device, path string) error {
	tool := commandPath("PYMOBILEDEVICE3_BIN", "pymobiledevice3")
	return runToFile("", path+".log", tool, "developer", "dvt", "screenshot", "--userspace", "--udid", device, path)
}

func deviceDebug(args []string) error {
	root, err := repositoryRoot()
	if err != nil {
		return err
	}
	if len(args) > 2 {
		return errors.New("usage: device-debug [DEVICE] [OUTPUT_DIRECTORY]")
	}
	device := deviceIdentifier(args)
	requested := ""
	if len(args) > 1 {
		requested = args[1]
	}
	output, err := outputDirectory(root, requested, "dearrow-device-")
	if err != nil {
		return err
	}
	if err := jbP1lotToFile(filepath.Join(output, "device-status.json"), device, "device_status"); err != nil {
		return err
	}
	if err := jbP1lotToFile(filepath.Join(output, "processes.json"), device, "process_manage", "--action", "list"); err != nil {
		return err
	}
	if err := jbP1lotShell(filepath.Join(output, "packages-and-crashes.json"), device, "dpkg-query -W -f='${Package} ${Version}\\n' dev.adrian.dearrow 2>/dev/null; ls -lt /var/mobile/Library/Logs/CrashReporter/YouTube-*.ips 2>/dev/null | head -5"); err != nil {
		return err
	}
	if err := captureDevice(device, filepath.Join(output, "screen.png")); err != nil {
		return err
	}
	if err := writeText(filepath.Join(output, "manifest.txt"), fmt.Sprintf("device=%s\nyoutube=%s\noutput=%s\n", device, youtubeBundleID, output)); err != nil {
		return err
	}
	fmt.Println(output)
	return nil
}

func simulatorIdentifier(args []string) string {
	if value := os.Getenv("DEARROW_SIMULATOR_ID"); value != "" {
		return value
	}
	if len(args) > 0 && args[0] != "" {
		return args[0]
	}
	return "booted"
}

func simulatorBoot(identifier string) error {
	if output, err := run("", "xcrun", "simctl", "bootstatus", identifier, "-b"); err == nil {
		_ = output
		return nil
	}
	if _, err := run("", "xcrun", "simctl", "boot", identifier); err != nil {
		return err
	}
	_, err := run("", "xcrun", "simctl", "bootstatus", identifier, "-b")
	return err
}

func simulatorCapture(identifier, path string) (int, int, error) {
	if _, err := run("", "xcrun", "simctl", "io", identifier, "screenshot", path); err != nil {
		return 0, 0, err
	}
	file, err := os.Open(path)
	if err != nil {
		return 0, 0, err
	}
	defer file.Close()
	configuration, _, err := image.DecodeConfig(file)
	if err != nil {
		return 0, 0, err
	}
	return configuration.Width, configuration.Height, nil
}

func simulatorRuntime(root, output string) (string, error) {
	dylib := os.Getenv("DEARROW_SIMULATOR_DYLIB")
	if dylib == "" {
		dylib = filepath.Join(root, ".theos", "obj", "arm64", "DeArrow.dylib")
	}
	substrate := os.Getenv("DEARROW_CYDIASUBSTRATE")
	if dylib == "" || substrate == "" {
		return "", nil
	}
	if _, err := os.Stat(dylib); err != nil {
		return "", err
	}
	if _, err := os.Stat(substrate); err != nil {
		return "", err
	}
	runtimeDirectory := filepath.Join(output, "runtime")
	frameworkDirectory := filepath.Join(runtimeDirectory, "CydiaSubstrate.framework")
	if err := os.MkdirAll(frameworkDirectory, 0755); err != nil {
		return "", err
	}
	convertedDylib := filepath.Join(runtimeDirectory, "DeArrow.dylib")
	convertedSubstrate := filepath.Join(frameworkDirectory, "CydiaSubstrate")
	if contents, err := os.ReadFile(dylib); err != nil {
		return "", err
	} else if err := os.WriteFile(convertedDylib, contents, 0755); err != nil {
		return "", err
	}
	if contents, err := os.ReadFile(substrate); err != nil {
		return "", err
	} else if err := os.WriteFile(convertedSubstrate, contents, 0755); err != nil {
		return "", err
	}
	simforge := commandPath("DEARROW_SIMFORGE_BIN", "simforge")
	if err := runToFile("", filepath.Join(output, "simforge-convert.log"), simforge, "convert", convertedDylib); err != nil {
		return "", err
	}
	convertedPath := convertedSubstrate + ".sim"
	if err := runToFile("", filepath.Join(output, "simulator-vtool.log"), "xcrun", "vtool", "-set-build-version", "iossim", "14.0", "14.0", "-replace", "-output", convertedPath, convertedSubstrate); err != nil {
		return "", err
	}
	if err := os.Rename(convertedPath, convertedSubstrate); err != nil {
		return "", err
	}
	if err := runToFile("", filepath.Join(output, "simulator-install-name.log"), "install_name_tool", "-add_rpath", runtimeDirectory, convertedDylib); err != nil {
		return "", err
	}
	if err := runToFile("", filepath.Join(output, "simulator-codesign.log"), "codesign", "-f", "-s", "-", convertedSubstrate, convertedDylib); err != nil {
		return "", err
	}
	return runtimeDirectory, nil
}

func launchSimulatorYouTube(identifier, runtimeDirectory, outputPath string) error {
	_, _ = run("", "xcrun", "simctl", "terminate", identifier, youtubeBundleID)
	environment := []string{}
	if runtimeDirectory != "" {
		environment = []string{
			"SIMCTL_CHILD_DYLD_FRAMEWORK_PATH=" + runtimeDirectory,
			"SIMCTL_CHILD_DYLD_INSERT_LIBRARIES=" + filepath.Join(runtimeDirectory, "DeArrow.dylib"),
		}
	}
	output, err := runWithEnvironment("", environment, "xcrun", "simctl", "launch", identifier, youtubeBundleID)
	if writeErr := writeText(outputPath, string(output)); err == nil && writeErr != nil {
		return writeErr
	}
	return err
}

func simulatorDebug(args []string) error {
	root, err := repositoryRoot()
	if err != nil {
		return err
	}
	if len(args) > 2 {
		return errors.New("usage: simulator-debug [SIMULATOR] [OUTPUT_DIRECTORY]")
	}
	identifier := simulatorIdentifier(args)
	requested := ""
	if len(args) > 1 {
		requested = args[1]
	}
	output, err := outputDirectory(root, requested, "dearrow-simulator-")
	if err != nil {
		return err
	}
	if err := simulatorBoot(identifier); err != nil {
		return err
	}
	if err := runToFile("", filepath.Join(output, "simulator-devices.txt"), "xcrun", "simctl", "list", "devices"); err != nil {
		return err
	}
	appsPath := filepath.Join(output, "youtube-app.txt")
	if err := runToFile("", appsPath, "xcrun", "simctl", "listapps", identifier); err != nil {
		return err
	}
	apps, err := os.ReadFile(appsPath)
	if err != nil {
		return err
	}
	if !strings.Contains(string(apps), youtubeBundleID) {
		return errors.New("YouTube is not installed on the selected simulator")
	}
	simslim := commandPath("DEARROW_SIMSLIM_BIN", "simslim")
	_ = runToFile("", filepath.Join(output, "simslim-status.txt"), simslim, "status", identifier)
	_ = runToFile("", filepath.Join(output, "simslim-verify.txt"), simslim, "verify", identifier)
	runtimeDirectory, err := simulatorRuntime(root, output)
	if err != nil {
		return err
	}
	injection := "disabled"
	if runtimeDirectory != "" {
		injection = runtimeDirectory
	}
	if err := writeText(filepath.Join(output, "runtime-path.txt"), injection+"\n"); err != nil {
		return err
	}
	if err := launchSimulatorYouTube(identifier, runtimeDirectory, filepath.Join(output, "launch.log")); err != nil {
		return err
	}
	if _, _, err := simulatorCapture(identifier, filepath.Join(output, "launch.png")); err != nil {
		return err
	}
	_ = runToFile("", filepath.Join(output, "youtube-logs.txt"), "xcrun", "simctl", "spawn", identifier, "log", "show", "--style", "compact", "--last", "5m", "--predicate", `process == "YouTube" OR eventMessage CONTAINS[c] "DeArrow"`)
	_ = runToFile("", filepath.Join(output, "simulator-memory.txt"), simslim, "measure", identifier)
	if err := writeText(filepath.Join(output, "manifest.txt"), fmt.Sprintf("simulator=%s\nyoutube=%s\ninjection=%s\noutput=%s\n", identifier, youtubeBundleID, injection, output)); err != nil {
		return err
	}
	fmt.Println(output)
	return nil
}

func simulatorWindowBounds() ([4]int, error) {
	var bounds [4]int
	output, err := run("", "osascript", "-e", `tell application "System Events" to tell process "Simulator" to get {position,size} of group 1 of window 1`)
	if err != nil {
		return bounds, err
	}
	if _, err := fmt.Sscanf(strings.TrimSpace(string(output)), "%d, %d, %d, %d", &bounds[0], &bounds[1], &bounds[2], &bounds[3]); err != nil {
		return bounds, err
	}
	return bounds, nil
}

func simulatorClick(identifier, screenshot string, x, y int) error {
	width, height, err := simulatorCapture(identifier, screenshot)
	if err != nil {
		return err
	}
	if _, err := run("", "open", "-a", "Simulator"); err != nil {
		return err
	}
	time.Sleep(300 * time.Millisecond)
	bounds, err := simulatorWindowBounds()
	if err != nil {
		return err
	}
	hostX := bounds[0] + int(float64(x)*float64(bounds[2])/float64(width))
	hostY := bounds[1] + int(float64(y)*float64(bounds[3])/float64(height))
	_, err = run("", commandPath("DEARROW_CLICLICK_BIN", "cliclick"), fmt.Sprintf("c:%d,%d", hostX, hostY))
	return err
}

func simulatorOCR(imagePath, textPath string) (string, error) {
	tesseract := commandPath("DEARROW_TESSERACT_BIN", "tesseract")
	base := strings.TrimSuffix(textPath, filepath.Ext(textPath))
	if _, err := run(filepath.Dir(imagePath), tesseract, filepath.Base(imagePath), filepath.Base(base)); err != nil {
		return "", err
	}
	contents, err := os.ReadFile(textPath)
	return strings.ToLower(string(contents)), err
}

func simulatorSettingsRegression(args []string) error {
	root, err := repositoryRoot()
	if err != nil {
		return err
	}
	if len(args) > 3 {
		return errors.New("usage: simulator-settings-regression [SIMULATOR] [OUTPUT_DIRECTORY] [OPEN_COUNT]")
	}
	identifier := simulatorIdentifier(args)
	requested := ""
	if len(args) > 1 {
		requested = args[1]
	}
	count := 20
	if len(args) > 2 {
		count, err = strconv.Atoi(args[2])
		if err != nil || count < 1 {
			return errors.New("open count must be positive")
		}
	}
	output, err := outputDirectory(root, requested, "dearrow-settings-")
	if err != nil {
		return err
	}
	if err := simulatorDebug([]string{identifier, output}); err != nil {
		return err
	}
	settingsX := 180
	settingsY := 97
	backX := 55
	backY := 260
	if value, parseErr := strconv.Atoi(os.Getenv("DEARROW_SIMULATOR_SETTINGS_X")); parseErr == nil {
		settingsX = value
	}
	if value, parseErr := strconv.Atoi(os.Getenv("DEARROW_SIMULATOR_SETTINGS_Y")); parseErr == nil {
		settingsY = value
	}
	if value, parseErr := strconv.Atoi(os.Getenv("DEARROW_SIMULATOR_BACK_X")); parseErr == nil {
		backX = value
	}
	if value, parseErr := strconv.Atoi(os.Getenv("DEARROW_SIMULATOR_BACK_Y")); parseErr == nil {
		backY = value
	}
	for index := 1; index <= count; index++ {
		if err := simulatorClick(identifier, filepath.Join(output, fmt.Sprintf("before-%02d.png", index)), settingsX, settingsY); err != nil {
			return err
		}
		time.Sleep(450 * time.Millisecond)
		pagePath := filepath.Join(output, fmt.Sprintf("open-%02d.png", index))
		if _, _, err := simulatorCapture(identifier, pagePath); err != nil {
			return err
		}
		text, err := simulatorOCR(pagePath, filepath.Join(output, fmt.Sprintf("open-%02d.txt", index)))
		if err != nil {
			return err
		}
		if !strings.Contains(text, "dearrow") || !strings.Contains(text, "donate") {
			return fmt.Errorf("custom DeArrow settings page was not visible on iteration %d", index)
		}
		if err := simulatorClick(identifier, filepath.Join(output, fmt.Sprintf("close-before-%02d.png", index)), backX, backY); err != nil {
			return err
		}
		time.Sleep(300 * time.Millisecond)
	}
	fmt.Println(output)
	return nil
}

func requireFile(root, relative string) ([]byte, error) {
	return os.ReadFile(filepath.Join(root, relative))
}

func requireContains(root, relative string, values ...string) error {
	contents, err := requireFile(root, relative)
	if err != nil {
		return err
	}
	text := string(contents)
	for _, value := range values {
		if !strings.Contains(text, value) {
			return fmt.Errorf("%s does not contain %q", relative, value)
		}
	}
	return nil
}

func requireExcludes(root, relative string, values ...string) error {
	contents, err := requireFile(root, relative)
	if err != nil {
		return err
	}
	text := string(contents)
	for _, value := range values {
		if strings.Contains(text, value) {
			return fmt.Errorf("%s contains forbidden %q", relative, value)
		}
	}
	return nil
}

func requireTreeExcludes(root, relative string, values ...string) error {
	return filepath.WalkDir(filepath.Join(root, relative), func(path string, entry os.DirEntry, err error) error {
		if err != nil {
			return err
		}
		if entry.IsDir() {
			return nil
		}
		contents, err := os.ReadFile(path)
		if err != nil {
			return err
		}
		for _, value := range values {
			if strings.Contains(string(contents), value) {
				relativePath, relativeErr := filepath.Rel(root, path)
				if relativeErr != nil {
					return relativeErr
				}
				return fmt.Errorf("%s contains forbidden %q", relativePath, value)
			}
		}
		return nil
	})
}

func verifyArchitecture(root string) error {
	if err := requireContains(root, "Makefile", "ARCHS = arm64 arm64e", "TARGET := iphone:clang:latest:15.0", "THEOS_PACKAGE_SCHEME = rootless", "sources"); err != nil {
		return err
	}
	if err := requireContains(root, "control", "Package: dev.adrian.dearrow", "Version:", "Depends: ellekit", "Replaces: com.pixelomer.dearrow-ios", "Conflicts: com.pixelomer.dearrow-ios"); err != nil {
		return err
	}
	if err := requireContains(root, "sources/BrandingClient.m", "NSURLSession", "NSCache", "requestBrandingForVideoID", "requestThumbnailForVideoID"); err != nil {
		return err
	}
	if err := requireContains(root, "sources/SettingsViewController.m", "Donate on Ko-fi", "What’s New", "Version"); err != nil {
		return err
	}
	if err := requireContains(root, "sources/SettingsIntegration.m", "SettingsIntegrationHostReady", "setSectionItems:forCategory:title:icon:titleDescription:headerHidden:"); err != nil {
		return err
	}
	if err := requireTreeExcludes(root, "sources", "ELMImageDownloader", "PXLDeArrow", "DeArrowCategoryPending"); err != nil {
		return err
	}
	if err := requireExcludes(root, "sources/SettingsIntegration.m", "setTitle:"); err != nil {
		return err
	}
	if err := requireContains(root, ".github/FUNDING.yml", "ko_fi: castdrian"); err != nil {
		return err
	}
	if _, err := os.Stat(filepath.Join(root, "layout", "Library", "Application Support", "DeArrow.bundle", "dearrow.png")); err == nil {
		return errors.New("unused raster DeArrow bundle image remains")
	}
	entries, err := os.ReadDir(filepath.Join(root, "scripts"))
	if err != nil {
		return err
	}
	for _, entry := range entries {
		if strings.HasSuffix(entry.Name(), ".py") || strings.HasSuffix(entry.Name(), ".sh") {
			return fmt.Errorf("legacy script remains: %s", entry.Name())
		}
	}
	fmt.Println("DeArrow architecture checks passed")
	return nil
}

func controlValue(root, key string) (string, error) {
	contents, err := requireFile(root, "control")
	if err != nil {
		return "", err
	}
	pattern := regexp.MustCompile(`(?m)^` + regexp.QuoteMeta(key) + `:[[:space:]]*(.+)$`)
	match := pattern.FindSubmatch(contents)
	if len(match) != 2 {
		return "", fmt.Errorf("control field %s is missing", key)
	}
	return strings.TrimSpace(string(match[1])), nil
}

func releaseDryRun(root string) error {
	packageName, err := controlValue(root, "Package")
	if err != nil {
		return err
	}
	version, err := controlValue(root, "Version")
	if err != nil {
		return err
	}
	if !regexp.MustCompile(`^[0-9]+\.[0-9]+\.[0-9]+$`).MatchString(version) {
		return fmt.Errorf("version %s is not semantic", version)
	}
	workflow, err := requireFile(root, ".github/workflows/release.yml")
	if err != nil {
		return err
	}
	workflowText := string(workflow)
	for _, value := range []string{"macos-latest", "gmake clean package", "softprops/action-gh-release", "package-update", "owner: 'castdrian'", "repo: 'apt-repo'"} {
		if !strings.Contains(workflowText, value) {
			return fmt.Errorf("release workflow does not contain %q", value)
		}
	}
	if strings.Contains(workflowText, "CHANGELOG.md\n          fail_on_unmatched_files") {
		return errors.New("release workflow attaches CHANGELOG.md directly")
	}
	fmt.Printf("release dry-run passed: %s %s\n", packageName, version)
	return nil
}

func usage() {
	fmt.Fprintln(os.Stderr, "usage: dearrow-tools COMMAND [ARGS]")
	fmt.Fprintln(os.Stderr, "commands: device-debug, simulator-debug, simulator-settings-regression, verify-architecture, release-dry-run")
}

func main() {
	if len(os.Args) < 2 {
		usage()
		os.Exit(2)
	}
	root, err := repositoryRoot()
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
	command := os.Args[1]
	args := os.Args[2:]
	switch command {
	case "device-debug":
		err = deviceDebug(args)
	case "simulator-debug":
		err = simulatorDebug(args)
	case "simulator-settings-regression":
		err = simulatorSettingsRegression(args)
	case "verify-architecture":
		if len(args) != 0 {
			err = errors.New("usage: verify-architecture")
		} else {
			err = verifyArchitecture(root)
		}
	case "release-dry-run":
		if len(args) != 0 {
			err = errors.New("usage: release-dry-run")
		} else {
			err = releaseDryRun(root)
		}
	default:
		usage()
		err = fmt.Errorf("unknown command %q", command)
	}
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}
