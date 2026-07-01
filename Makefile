.PHONY: build run app app-debug install clean test

# Default: just compile
build:
	swift build

# Compile (debug) and run as CLI binary — useful during dev
run:
	swift run NTFSAccess

# Build a real .app bundle in ./build (release config, ad-hoc signed)
app:
	./Scripts/build_app.sh

# Same, but debug build (faster compile, larger binary, easier symbolication)
app-debug:
	./Scripts/build_app.sh --debug

# Build .app and copy to /Applications
install:
	./Scripts/build_app.sh --install

# Open the built bundle
open:
	open "build/NTFS For Mac.app"

clean:
	rm -rf .build build

test:
	swift test
