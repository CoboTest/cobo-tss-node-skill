# Release Procedure

## Checklist

1. **All tests pass**
   ```bash
   bash tests/run-tests.sh
   ```

2. **Update version in all locations**
   - `SKILL.md` → `version: X.Y.Z` (frontmatter)
   - `README.md` → badge: `version-X.Y.Z-blue`
   - `CHANGELOG.md` → add `## [X.Y.Z] - YYYY-MM-DD` section + comparison link at bottom

3. **Write CHANGELOG entry**
   - Follow [Keep a Changelog](https://keepachangelog.com/) format
   - Sections: Added / Changed / Fixed / Removed
   - Add comparison link: `[X.Y.Z]: https://github.com/CoboTest/cobo-tss-node-skill/compare/vPREV...vX.Y.Z`

4. **Commit + push**
   ```bash
   git add -A
   git commit -m "release: vX.Y.Z — <summary>"
   git push origin main
   ```

5. **Tag**
   ```bash
   git tag -a vX.Y.Z -m "vX.Y.Z: <summary>"
   git push origin vX.Y.Z
   ```

6. **Sync to workspace**
   ```bash
   rsync -av --delete --exclude .git ~/codes/cobo-tss-node-skill/ ~/.openclaw/workspace/skills/cobo-tss-node/
   ```

7. **Publish to ClawHub** (only when explicitly requested by d15)
   ```bash
   clawhub publish ~/.openclaw/workspace/skills/cobo-tss-node/ \
     --slug cobo-tss-node --name "Cobo TSS Node" \
     --version X.Y.Z --changelog "<summary>"
   ```

## Version Locations Quick Reference

| File | Field | Example |
|------|-------|---------|
| `SKILL.md` | `version:` in YAML frontmatter | `version: 0.4.0` |
| `README.md` | Badge URL | `version-0.4.0-blue` |
| `CHANGELOG.md` | Section header + link | `## [0.4.0] - 2026-02-27` |

## Versioning

Follow [SemVer](https://semver.org/):
- **MAJOR**: breaking changes to skill interface or script args
- **MINOR**: new features, new scripts, new commands
- **PATCH**: bug fixes, docs, test improvements
