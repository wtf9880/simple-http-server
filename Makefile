fmt:
	cargo fmt --all -- --check

clippy:
	cargo clippy --workspace --all-targets --all-features -- -D warnings

test: export RUST_BACKTRACE := full
test:
	RUSTFLAGS='-D warnings' cargo test --workspace --all-features

ci: fmt clippy test
	git diff --exit-code Cargo.lock

.PHONY: fmt clippy test ci
