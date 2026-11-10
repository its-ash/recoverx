STORE_ID := recoverx

.PHONY: run build clean

run:
	flutter run

build:
	dart run build_runner build --delete-conflicting-outputs
	flutter build apk --release --target-platform android-arm64

clean:
	flutter clean
	rm -rf dist

# deploy, release, bump, store-check, store-meta, version
include store.mk
