#!/usr/bin/env bash
#
# Re-applies the fork's customizations on top of upstream-owned files.
#
# Idempotent: safe to run on a fresh upstream checkout or on an already
# patched tree. Fails loudly (non-zero exit) when an anchor it relies on has
# moved upstream, so a silent half-patch can never be committed.
#
# Fork-only files that need no patching (never touched by upstream):
#   .github/workflows/publish-docker-image.yaml
#   .github/workflows/sync-upstream.yml, tag-synced-release.yml
#   src/services/proxyFetch.ts, tests/proxyFetch.test.ts
#   .github/fork/*
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

die() { echo "::error::apply-fork-changes: $*" >&2; exit 1; }

# ── 1. Docker image publishing replaces the upstream ECR deploy ──────────────
rm -f .github/workflows/deploy.yml

# ── 2. CI: Node 24 only, tests run once (with coverage) ──────────────────────
ci=.github/workflows/ci.yml
[ -f "$ci" ] || die "$ci missing"
if ! grep -q 'name: Test with coverage' "$ci"; then
  python3 - "$ci" <<'PY'
import re, sys
path = sys.argv[1]
s = open(path).read()

def replace_once(s, old, new, what):
    if s.count(old) != 1:
        sys.exit(f"ci.yml: anchor not found or ambiguous ({what}) - upstream layout changed?")
    return s.replace(old, new, 1)

s = replace_once(s, "node-version: [20, 22]", "node-version: [24]", "node matrix")

# `pnpm run check` already includes the tests, and coverage then ran them a
# second time. Run the static checks individually and the tests once.
check = re.search(
    r"      - name: Check \([^\n]*\)\n        run: pnpm run check\n\n"
    r"      - name: Generate coverage report\n        if: matrix\.node-version == 22\n"
    r"        run: pnpm run test:coverage\n", s)
if not check:
    sys.exit("ci.yml: check/coverage steps not found - upstream layout changed?")
split = """      # Static checks run individually so the test suite runs only once - via
      # test:coverage below - instead of twice (pnpm run check already includes
      # the tests).
      - name: Typecheck
        run: pnpm run typecheck

      - name: Typecheck tests
        run: pnpm run typecheck:tests

      - name: Lint
        run: pnpm run lint

      - name: Format check
        run: pnpm run format:check

      - name: Test with coverage
        run: pnpm run test:coverage

      - name: Build
        run: pnpm run build
"""
s = s[:check.start()] + split + s[check.end():]
s = replace_once(s, "if: matrix.node-version == 22", "if: matrix.node-version == 24", "coverage upload condition")
open(path, "w").write(s)
PY
fi
grep -q 'node-version: \[24\]' "$ci" || die "ci.yml: Node 24 matrix missing after patch"

# ── 3. Dockerfile: Node 24 base images ───────────────────────────────────────
sed -i -E 's/^FROM node:22-alpine/FROM node:24-alpine/' Dockerfile
[ "$(grep -c '^FROM node:24-alpine' Dockerfile)" -ge 2 ] || die "Dockerfile: expected 2 node:24-alpine stages"

# ── 4. release.yml: keep only the `release` job, on Node 24 ──────────────────
# Upstream's npm publishing and ECR build+deploy jobs are dropped: this fork
# publishes its image via publish-docker-image.yaml.
rel=.github/workflows/release.yml
[ -f "$rel" ] || die "$rel missing"
python3 - "$rel" <<'PY'
import re, sys
path = sys.argv[1]
drop = {"publish-npm", "publish-registry", "build-image", "deploy-gateway", "deploy-lightsail"}
out, skipping, seen = [], False, set()
for line in open(path).read().split("\n"):
    m = re.match(r"^  ([A-Za-z0-9_-]+):\s*$", line)
    if m:                         # a top-level job starts
        seen.add(m.group(1))
        skipping = m.group(1) in drop
    elif re.match(r"^\S", line):  # left the `jobs:` block
        skipping = False
    if not skipping:
        out.append(line)
if "release" not in seen:
    sys.exit("release.yml: `release` job not found (upstream layout changed?)")
text = "\n".join(out).rstrip("\n") + "\n"
text = re.sub(r"(node-version:\s*)22\b", r"\g<1>24", text)
open(path, "w").write(text)
PY
grep -q '^  release:' "$rel" || die "release.yml: release job lost"
if grep -qE '^  (publish-npm|publish-registry|build-image|deploy-gateway|deploy-lightsail):' "$rel"; then
  die "release.yml: a dropped job is still present"
fi

# ── 5. Proxy: route every Cellar/SPARQL request through proxyFetch ───────────
[ -f src/services/proxyFetch.ts ] || die "src/services/proxyFetch.ts missing (fork-only file)"
cc=src/services/cellarClient.ts
[ -f "$cc" ] || die "$cc missing (upstream layout changed? re-point the proxy patch)"
if ! grep -q 'proxyFetch' "$cc"; then
  python3 - "$cc" <<'PY'
import re, sys
path = sys.argv[1]
s = open(path).read()
anchor = "import { TtlCache } from './ttlCache.js';\n"
if s.count(anchor) != 1:
    sys.exit("cellarClient.ts: TtlCache import anchor not found (upstream layout changed?)")
s = s.replace(anchor, "import { proxyFetch } from './proxyFetch.js';\n" + anchor, 1)
# Every direct global fetch call, however many upstream has now (4 in v2.4.4).
s, n = re.subn(r"(?<![.\w])fetch\(", "proxyFetch(", s)
if n < 1:
    sys.exit("cellarClient.ts: no fetch() calls found (upstream layout changed?)")
print(f"cellarClient.ts: routed {n} fetch() call(s) through proxyFetch")
open(path, "w").write(s)
PY
fi
# Guard: nothing else in src/ may call the global fetch directly, otherwise it
# would silently bypass the proxy.
if grep -rnE '(^|[^.A-Za-z_])fetch\(' src --include='*.ts' --exclude=proxyFetch.ts \
     | grep -vE '^\S+:[0-9]+:\s*(//|\*|/\*)'; then
  die "direct fetch() calls found in src/ - route them through proxyFetch"
fi

# ── 6. package.json: undici dependency ───────────────────────────────────────
node - <<'JS'
const fs = require('node:fs');
const pkg = JSON.parse(fs.readFileSync('package.json', 'utf8'));
pkg.dependencies = { ...pkg.dependencies, undici: '^8.2.0' };
pkg.dependencies = Object.fromEntries(Object.entries(pkg.dependencies).sort(([a], [b]) => a.localeCompare(b)));
fs.writeFileSync('package.json', JSON.stringify(pkg, null, 2) + '\n');
JS

# ── 7. Lockfile: regenerate instead of replaying a stale diff ───────────────
if command -v pnpm >/dev/null 2>&1; then
  pnpm install --lockfile-only --no-frozen-lockfile
else
  echo "pnpm not found - skipping lockfile refresh" >&2
fi

echo "apply-fork-changes: done"
