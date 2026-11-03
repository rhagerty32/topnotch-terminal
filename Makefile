.PHONY: generate build open release dmg

generate:
	xcodegen generate

build: generate
	DEVELOPER_DIR="$$(bash scripts/metal-developer-dir.sh)" xcodebuild -scheme TopNotchTerminal -configuration Debug -derivedDataPath build -destination 'platform=macOS' build

open: build
	# Same bundle id stays resident in the notch — `open` would only
	# activate that old process and hide a fresh build.
	-killall "TopNotch Terminal" 2>/dev/null
	sleep 0.3
	open "build/Build/Products/Debug/TopNotch Terminal.app"

release: generate
	DEVELOPER_DIR="$$(bash scripts/metal-developer-dir.sh)" xcodebuild -scheme TopNotchTerminal -configuration Release -derivedDataPath build -destination 'platform=macOS' build

dmg:
	bash scripts/package-dmg.sh
