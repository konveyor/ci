#!/usr/bin/env python3
"""
Parse nightly matrix config YAML and organize jobs by dependency levels.

This script reads a YAML configuration file and creates a multi-level array
where each level represents a dependency depth in the job tree.
"""

import sys
import json
import yaml
import argparse
import subprocess
from pathlib import Path
from typing import List, Dict, Any, Optional, Tuple
from collections import defaultdict


def replace_branch_placeholder(obj: Any, branch_name: str) -> Any:
    """
    Recursively replace BRANCH_PLACEHOLDER with the actual branch name in any data structure.

    Args:
        obj: The object to process (dict, list, str, or other)
        branch_name: The branch name to replace BRANCH_PLACEHOLDER with

    Returns:
        The object with all BRANCH_PLACEHOLDER occurrences replaced
    """
    if isinstance(obj, dict):
        return {k: replace_branch_placeholder(v, branch_name) for k, v in obj.items()}
    elif isinstance(obj, list):
        return [replace_branch_placeholder(item, branch_name) for item in obj]
    elif isinstance(obj, str):
        return obj.replace("BRANCH_PLACEHOLDER", branch_name)
    else:
        return obj


def parse_overrides(overrides_json: str) -> Dict[str, str]:
    """
    Parse the overrides JSON list into a dict mapping repo to PR ref.

    Each entry is in the format "<org>/<repo>#<pr-number>".
    Returns a dict like {"konveyor/kantra": "refs/pull/123/merge"}.

    Args:
        overrides_json: JSON string like '["konveyor/kantra#123", ...]'

    Returns:
        Dict mapping repo name to canonical GitHub PR ref
    """
    overrides = {}
    try:
        entries = json.loads(overrides_json)
    except (json.JSONDecodeError, TypeError):
        return overrides

    for entry in entries:
        if "#" not in entry:
            print(
                f"Warning: Skipping invalid override (missing #): {entry}",
                file=sys.stderr,
            )
            continue
        repo, pr_number = entry.rsplit("#", 1)
        if not pr_number.isdigit():
            print(
                f"Warning: Skipping invalid override (non-numeric PR): {entry}",
                file=sys.stderr,
            )
            continue
        overrides[repo] = f"refs/pull/{pr_number}/merge"

    return overrides


def _module_matches_repo(module_path: str, repo: str) -> bool:
    """Check if a Go module path corresponds to a GitHub repo.

    Args:
        module_path: Go module path (e.g., "github.com/konveyor/analyzer-lsp/external-providers/...")
        repo: GitHub repo (e.g., "konveyor/analyzer-lsp")

    Returns:
        True if the module belongs to the repo
    """
    prefix = f"github.com/{repo}"
    return module_path == prefix or module_path.startswith(f"{prefix}/")


def _build_replace_target(
    module_path: str, source_repo: str, fork_repo: str, branch: str
) -> str:
    """Build a go mod replace target, preserving any submodule path.

    For root modules (e.g., github.com/konveyor/analyzer-lsp), the target is
    github.com/<fork>@<branch>.

    For submodules (e.g., github.com/konveyor/analyzer-lsp/external-providers/java-external-provider),
    the subpath is preserved: github.com/<fork>/external-providers/java-external-provider@<branch>.

    Args:
        module_path: The full Go module path being replaced
        source_repo: The upstream repo (e.g., "konveyor/analyzer-lsp")
        fork_repo: The fork repo (e.g., "shawn-hurley/analyzer-lsp")
        branch: The branch name on the fork

    Returns:
        The replace target string (e.g., "github.com/shawn-hurley/analyzer-lsp/subpath@branch")
    """
    source_prefix = f"github.com/{source_repo}"
    subpath = module_path[
        len(source_prefix) :
    ]  # "" for root, "/external-providers/..." for submodules
    return f"github.com/{fork_repo}{subpath}@{branch}"


def resolve_pr_head_info(repo: str, pr_number: str) -> Optional[Dict[str, str]]:
    """Resolve a PR's head fork repo and branch using the GitHub CLI.

    Args:
        repo: GitHub repo (e.g., "konveyor/analyzer-lsp")
        pr_number: PR number

    Returns:
        Dict with "fork_repo" and "branch" keys, or None if resolution fails
    """
    try:
        result = subprocess.run(
            [
                "gh",
                "api",
                f"repos/{repo}/pulls/{pr_number}",
                "--jq",
                "[.head.repo.full_name, .head.ref] | @tsv",
            ],
            capture_output=True,
            text=True,
            timeout=30,
        )
        if result.returncode == 0 and result.stdout.strip():
            fork_repo, branch = result.stdout.strip().split("\t")
            return {"fork_repo": fork_repo, "branch": branch}
        print(
            f"Warning: Failed to resolve PR info for {repo}#{pr_number}: {result.stderr.strip()}",
            file=sys.stderr,
        )
    except FileNotFoundError:
        print("Warning: gh CLI not found, cannot resolve PR info", file=sys.stderr)
    except subprocess.TimeoutExpired:
        print(
            f"Warning: Timed out resolving PR info for {repo}#{pr_number}",
            file=sys.stderr,
        )
    except ValueError:
        print(
            f"Warning: Unexpected API response for {repo}#{pr_number}",
            file=sys.stderr,
        )
    return None


def apply_go_mod_replaces(
    levels: List[List[Dict[str, Any]]],
    tested_repo: str,
    tested_repo_fork: str,
    tested_repo_branch: str,
    ref_overrides: Dict[str, str],
) -> None:
    """Add go_mod_replaces entries for images that need fork-based module replacements.

    For overridden images: if go_mod_update references the tested repo's module,
    add a go_mod_replaces entry pointing to the tested repo's fork and branch.

    For tested repo images: if go_mod_update references an overridden repo's module,
    resolve that PR's fork info and add a go_mod_replaces entry.

    Args:
        levels: The organized job levels (modified in place)
        tested_repo: The repo under test (from -r flag)
        tested_repo_fork: Fork repo for the tested PR (e.g., "shawn-hurley/analyzer-lsp")
        tested_repo_branch: Branch name on the fork
        ref_overrides: Dict mapping repo -> refs/pull/N/merge
    """
    # Cache for lazily resolved override PR info
    override_info_cache: Dict[str, Optional[Dict[str, str]]] = {}

    for level in levels:
        for job in level:
            if "go_mod_update" not in job:
                continue

            replaces = []
            for entry in job["go_mod_update"]:
                if "@" not in entry:
                    continue

                module_path, _branch = entry.rsplit("@", 1)

                # Case 1: Overridden image references the tested repo's module
                if job.get("ref") and _module_matches_repo(module_path, tested_repo):
                    target = _build_replace_target(
                        module_path, tested_repo, tested_repo_fork, tested_repo_branch
                    )
                    replace = f"{module_path}={target}"
                    replaces.append(replace)
                    print(f"  go_mod_replaces: {module_path} -> {target}")
                    continue

                # Case 2: Tested repo's image references an overridden repo's module
                if job.get("repo") == tested_repo:
                    for override_repo in ref_overrides:
                        if _module_matches_repo(module_path, override_repo):
                            if override_repo not in override_info_cache:
                                pr_number = ref_overrides[override_repo].split("/")[2]
                                override_info_cache[override_repo] = (
                                    resolve_pr_head_info(override_repo, pr_number)
                                )
                            info = override_info_cache[override_repo]
                            if info is None:
                                print(
                                    f"Error: Could not resolve PR info for override {override_repo} "
                                    f"(ref: {ref_overrides[override_repo]}). "
                                    f"Cannot build go_mod_replaces for {module_path}.",
                                    file=sys.stderr,
                                )
                                sys.exit(1)
                            target = _build_replace_target(
                                module_path,
                                override_repo,
                                info["fork_repo"],
                                info["branch"],
                            )
                            replace = f"{module_path}={target}"
                            replaces.append(replace)
                            print(f"  go_mod_replaces: {module_path} -> {target}")
                            break

            if replaces:
                job["go_mod_replaces"] = replaces


def organize_by_levels(
    config_items: List[Dict[str, Any]],
    base_image_tag: str = None,
    repo_filter: str = None,
    ref_overrides: Dict[str, str] = None,
) -> List[List[Dict[str, Any]]]:
    """
    Organize configuration items into levels based on dependency depth.

    Args:
        config_items: List of configuration dictionaries from the YAML
        base_image_tag: Optional tag to append to base_image (e.g., "nightly", "v1.0")
        repo_filter: Optional repository name to filter jobs at any level (e.g., "konveyor/kantra")
        ref_overrides: Optional dict mapping repo names to refs (e.g., {"konveyor/kantra": "refs/pull/123/merge"})

    Returns:
        List of lists, where each inner list contains jobs at that dependency level
    """
    levels = defaultdict(list)

    def find_and_process_matching_jobs(
        job: Dict[str, Any],
        level: int,
        parent_image: Optional[str] = None,
        include: bool = False,
    ) -> bool:
        """
        Recursively search for jobs matching the repo filter and process them.

        Args:
            job: The job to process
            level: Current dependency level
            parent_image: Parent image for base_image field
            include: Whether this job should be included (parent was matched)

        Returns:
            True if this job or any descendant matches the filter
        """
        # Check if this job matches the filter
        matches = repo_filter is None or job.get("repo") == repo_filter

        # Check if any dependent jobs match (look ahead)
        has_matching_descendant = False
        if "dependent_jobs" in job:
            for dependent_job in job["dependent_jobs"]:
                if find_and_process_matching_jobs(
                    dependent_job, level + 1, job.get("image"), include or matches
                ):
                    has_matching_descendant = True

        # Include this job if it matches or we're already including (parent matched)
        # Don't include just because of matching descendants
        if matches or include:
            job_copy = {k: v for k, v in job.items() if k != "dependent_jobs"}

            # Add base_image field for dependent jobs
            if parent_image:
                parent_image = parent_image.replace("/", "_")
                if base_image_tag:
                    job_copy["base_image"] = f"{parent_image}--{base_image_tag}"
                else:
                    job_copy["base_image"] = parent_image

            # Apply ref override if this repo has one
            if ref_overrides and job_copy.get("repo") in ref_overrides:
                job_copy["ref"] = ref_overrides[job_copy["repo"]]

            levels[level].append(job_copy)
            return True

        return has_matching_descendant

    # Process all top-level jobs
    for job in config_items:
        find_and_process_matching_jobs(job, 0)

    # Convert defaultdict to sorted list of lists
    max_level = max(levels.keys()) if levels else 0
    return [levels[i] for i in range(max_level + 1)]


def main():
    """Main entry point for the script."""
    parser = argparse.ArgumentParser(
        description="Parse nightly matrix config YAML and organize jobs by dependency levels."
    )
    parser.add_argument("yaml_file", help="Path to the YAML configuration file")
    parser.add_argument(
        "output_dir", nargs="?", help="Optional output directory for JSON files"
    )
    parser.add_argument(
        "-t", "--tag", help='Tag to append to base_image (e.g., "nightly", "v1.0")'
    )
    parser.add_argument(
        "-b", "--branch", help="Branch name to replace BRANCH_PLACEHOLDER with"
    )
    parser.add_argument(
        "-r",
        "--repo",
        help='Filter to only include jobs from this repository (e.g., "konveyor/kantra"). Dependent jobs will still be included.',
    )
    parser.add_argument(
        "-o",
        "--overrides",
        help="JSON list of repo#PR overrides (e.g., '[\"konveyor/kantra#123\"]'). "
        "Sets the ref for matching repos to refs/pull/<pr>/merge.",
    )
    parser.add_argument(
        "--tested-repo-head",
        help="Fork repo and branch of the tested PR in 'fork_repo:branch' format "
        '(e.g., "shawn-hurley/analyzer-lsp:my-feature"). Used to generate '
        "go_mod_replaces for overridden images that depend on the tested repo.",
    )

    args = parser.parse_args()

    try:
        # Read and parse the YAML file
        with open(args.yaml_file, "r") as f:
            data = yaml.safe_load(f)

        if "config" not in data:
            print("Error: YAML file must contain a 'config' key", file=sys.stderr)
            sys.exit(1)

        # Replace BRANCH_PLACEHOLDER if branch is specified
        if args.branch:
            data = replace_branch_placeholder(data, args.branch)

        # Parse ref overrides from CI comments
        ref_overrides = parse_overrides(args.overrides) if args.overrides else None

        # Organize jobs by dependency levels
        levels = organize_by_levels(data["config"], args.tag, args.repo, ref_overrides)

        # Add go_mod_replaces entries when overrides are present
        if ref_overrides and args.repo and args.tested_repo_head:
            fork_repo, branch = args.tested_repo_head.split(":", 1)
            print("Applying go_mod_replaces:")
            apply_go_mod_replaces(levels, args.repo, fork_repo, branch, ref_overrides)
            print()

        # Print the results summary
        print(f"Found {len(levels)} dependency levels:\n")

        for level_idx, jobs in enumerate(levels):
            print(f"Level {level_idx} ({len(jobs)} jobs):")
            for job in jobs:
                base = f" (base: {job['base_image']})" if "base_image" in job else ""
                print(
                    f"  - {job.get('repo', 'unknown')} -> {job.get('image', 'unknown')}{base}"
                )
            print()

        # Write each level to a separate JSON file if output directory is specified
        if args.output_dir:
            output_path = Path(args.output_dir)
            output_path.mkdir(parents=True, exist_ok=True)

            # Always write 4 level files (0-3) even if some are empty
            # This ensures workflows can always read all expected files
            max_levels = 4
            for level_idx in range(max_levels):
                output_file = output_path / f"level_{level_idx}.json"
                # Get jobs for this level, or empty list if level doesn't exist
                jobs = levels[level_idx] if level_idx < len(levels) else []
                with open(output_file, "w") as f:
                    output = {
                        "image": jobs,
                        "os": [
                            {"arch": "arm64", "runner": "ubuntu-24.04-arm"},
                            {"arch": "amd64", "runner": "ubuntu-latest"},
                        ],
                    }
                    json.dump(output, f, indent=2)
                print(f"Wrote {len(jobs)} jobs to {output_file}")

            # Also write all levels combined
            all_levels_file = output_path / "all_levels.json"
            with open(all_levels_file, "w") as f:
                json.dump(levels, f, indent=2)
            print(f"\nWrote all levels to {all_levels_file}")
        else:
            # Output all levels as JSON to stdout
            print("\nJSON Output:")
            print(json.dumps(levels, indent=2))

    except FileNotFoundError:
        print(f"Error: File '{args.yaml_file}' not found", file=sys.stderr)
        sys.exit(1)
    except yaml.YAMLError as e:
        print(f"Error parsing YAML: {e}", file=sys.stderr)
        sys.exit(1)
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
