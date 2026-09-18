.PHONY: run build deploy

run:
	flutter run

build:
	dart run build_runner build --delete-conflicting-outputs
	flutter build apk --release --target-platform android-arm64

deploy: build
	@v=$$(node -e "const f=require('fs').readFileSync('pubspec.yaml','utf8');const m=f.match(/version:\s*(\d+)\.(\d+)\.(\d+)\+(\d+)/);if(!m)process.exit(1);const[major,minor,patch,build]=m.slice(1).map(Number);console.log(major+'.'+minor+'.'+(patch+1)+'+'+(build+1))") && \
		sed -i '' -E "s/^version: .+/version: $$v/" pubspec.yaml && \
		echo "Bumped version to $$v"
	@TAG="v$$(node -e "const f=require('fs').readFileSync('pubspec.yaml','utf8');const m=f.match(/version:\s*(\d+\.\d+\.\d+)/);console.log(m[1])")" && \
		echo "Creating release $$TAG"
	git checkout main
	git add -A
	git commit -m "$$(copilot -sp 'Analyze the staged git changes and generate a concise commit message. Output ONLY the commit message. Do not execute any commands. Do not include quotes, markdown, explanation, or bullet points.')"
	git push origin main
	@TAG="v$$(node -e "const f=require('fs').readFileSync('pubspec.yaml','utf8');const m=f.match(/version:\s*(\d+\.\d+\.\d+)/);console.log(m[1])")" && \
		NOTES="$$(copilot -sp 'Generate a concise GitHub release notes body for a new release of RecoverX, an Android data-recovery app that scans for deleted files using binary file signatures (magic numbers). Summarize the key changes from the recent git commits. Output ONLY the release notes in markdown. Do not execute any commands. Do not include quotes or explanation.')" && \
		gh release create "$$TAG" \
			--title "RecoverX $$TAG" \
			--notes "$$NOTES" \
			build/app/outputs/flutter-apk/app-release.apk