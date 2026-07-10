# One entry point for the fast gate. It runs the backend unit tests and the
# Swift Testing suite and is the single meaning of green.

.PHONY: gate gate-backend gate-app pipeline dmg app-bundle

gate: gate-backend gate-app

gate-backend:
	cd backend && uv run pytest -q -m "not pipeline and not manual"

# On a machine with only the Command Line Tools, Testing.framework lives in a
# directory SwiftPM does not search by default. With full Xcode installed the
# directory is absent and the flags collapse to nothing.
CLT_FRAMEWORKS := /Library/Developer/CommandLineTools/Library/Developer/Frameworks
SWIFT_TEST_FLAGS := $(shell test -d $(CLT_FRAMEWORKS) && echo "-Xswiftc -F -Xswiftc $(CLT_FRAMEWORKS) -Xswiftc -Xfrontend -Xswiftc -disable-cross-import-overlays -Xlinker -F -Xlinker $(CLT_FRAMEWORKS) -Xlinker -rpath -Xlinker $(CLT_FRAMEWORKS)")

gate-app:
	cd app && swift test $(SWIFT_TEST_FLAGS)

# Slow tier: the real MLX speech models against the user's recorded fixtures, on
# the reference machine. Run at phase boundaries. Needs the models extra
# (uv sync --extra models) and the voice fixtures.
pipeline:
	cd backend && uv run pytest -q -m pipeline

app-bundle:
	bash scripts/build_app.sh

dmg: app-bundle
	bash scripts/build_dmg.sh
