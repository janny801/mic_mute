.PHONY: all build release run clean

all: release

build:
	@./scripts/build_app.sh debug

release:
	@./scripts/build_app.sh release

run: release
	@echo "==> Launching MicMute.app..."
	@open build/MicMute.app

clean:
	@rm -rf .build build
	@echo "==> Cleaned build artifacts."
