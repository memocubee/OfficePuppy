.PHONY: generate build test clean lint release

# Generate Xcode project from project.yml
generate:
	xcodegen generate

# Build the app
build: generate
	xcodebuild -project OfficePuppy.xcodeproj \
		-scheme OfficePuppy \
		-configuration Release \
		-derivedDataPath build \
		build

# Run tests
test: generate
	xcodebuild -project OfficePuppy.xcodeproj \
		-scheme OfficePuppyTests \
		-configuration Debug \
		-derivedDataPath build \
		test

# Clean build artifacts
clean:
	rm -rf build/ DerivedData/

# Run SwiftLint
lint:
	swiftlint lint --config .swiftlint.yml

# Create DMG for distribution
dmg: build
	./scripts/create-dmg.sh

# Full release pipeline (local)
release: build dmg
	@echo "Release build complete. DMG at build/OfficePuppy.dmg"
