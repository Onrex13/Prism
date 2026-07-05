.PHONY: build run app dmg release cert clean icon

# Debug build
build:
	swift build

# Build the release .app and launch it
run: app
	@echo "▸ Launching Prism…"
	@open dist/Prism.app

# Assemble the distributable .app bundle
app: icon
	@bash Scripts/build_app.sh

# Generate the app icon (.icns) from the SVG source
icon:
	@bash Scripts/make_icon.sh

# Build the final .dmg
dmg: app
	@bash Scripts/make_dmg.sh

# Build both release artifacts (.dmg + .zip) for a GitHub release
release:
	@bash Scripts/make_release.sh

# One-time: create the stable self-signed signing identity (update-safe perms)
cert:
	@bash Scripts/make_cert.sh

clean:
	rm -rf .build dist
