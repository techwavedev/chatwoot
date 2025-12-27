# Fork Maintenance

This document tracks custom changes made to this fork of Chatwoot and outlines the strategy for effective maintenance and upstream merging.

## Fork Information

- **Fork Repository**: `https://github.com/techwavedev/chatwoot`
- **Upstream Repository**: `https://github.com/chatwoot/chatwoot` (Official)

## Maintenance Strategy

To keep this fork up-to-date with upstream while preserving custom changes:

1.  **Add Upstream Remote**:
    ```bash
    git remote add upstream https://github.com/chatwoot/chatwoot.git
    ```

2.  **Fetch Upstream Changes**:
    ```bash
    git fetch upstream
    ```

3.  **Merge Upstream into Local Main/Dev**:
    ```bash
    git checkout main
    git merge upstream/master
    # Resolve conflicts if any
    ```

4.  **Re-apply Custom Changes if needed**:
    Review the [Change Log](#change-log) to ensure custom functionality persists after merging.

## Change Log

| Date | Commit | Description | Files Modified | Reason/Context |
|------|--------|-------------|----------------|----------------|
| 2024-12-28 | `8f61d9d` | build: Add `--pull` flag to `docker buildx build` command | `.github/workflows/docker.yaml` (implied) | Ensure base images are always pulled for security/freshness. |
| 2024-12-28 | `e03a042` | feat: Add script to automate Docker image and service builds | `bin/docker-build` | Simplify local development and build process. |
| 2024-12-28 | `7abe9d7` | chore: update .gitignore to exclude .windsurf type files | `.gitignore` | Exclude IDE/editor specific files. |

## Moving Forward

- **Before Committing**: Check if the change is specific to this fork or could be contributed upstream.
- **Log all Changes**: Update this table for every PR/Commit that introduces fork-specific deviations.
