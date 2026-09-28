.PHONY: all build release run install clean

all: release

build:
	@./scripts/build_app.sh debug

release:
	@./scripts/build_app.sh release

install: release
	@echo "==> Installing MicMute.app to /Applications..."
	@rm -rf /Applications/MicMute.app
	@cp -R build/MicMute.app /Applications/
	@echo "==> Installed to /Applications/MicMute.app"

run: install
	@echo "==> Launching MicMute.app..."
	@open /Applications/MicMute.app

clean:
	@rm -rf .build build
	@echo "==> Cleaned build artifacts."
