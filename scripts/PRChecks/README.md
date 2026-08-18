# PR Checklist

The purpose of the checklists are to catch common issues with pull requests.

The checklist runs...

* After the PR submit or change tests are run.
* Every night on PRs that already have a checklist to see if items have been fixed.
* When an admin adds the `run-checklist` label to a PR.

## `addPRChecklistIfNeeded.sh`

```sh
addPRChecklistIfNeeded.sh --repo=<github org/repo> --pr-number=<PR number to check/update> [ --dry-run ]
```

The `.github/workflows/AsteriskPRCheck.yml` workflow calls `addPRChecklistIfNeeded.sh` in its PostWorkflow job.  `--repo` and `pr-number` come from the GitHub event payload.

The script does the following...

* Downloads the PR's json document from `https://api.github.com/repos/${REPO}/pulls/${PR_NUMBER}` to `/tmp/pr-${PR_NUMBER}.json`
* Downloads the PR's diff from `https://github.com/${REPO}/pull/${PR_NUMBER}.diff` to `/tmp/pr-${PR_NUMBER}.diff`
* Downloads the PR's "commits" json document from `https://api.github.com/repos/${REPO}/pulls/${PR_NUMBER}/commits` to `/tmp/pr-commits-${PR_NUMBER}.json`
* Downloads the PR's "comments" json document from `https://api.github.com/repos/${REPO}/issues/${PR_NUMBER}/comments` to `/tmp/pr-comments-${PR_NUMBER}.json`
* Runs each of the check scripts in this directory in sequence which append their output (if any) to `/tmp/pr-checklist-${PR_NUMBER}.md`
* Finds the ID of any existing checklist on the PR.
* If no checks have created checklist items...
    * Any existing checklist is deleted since it's obsolete.
    * The script ends.
* If checks have created checklist items...
    * If there was an existing PR comment with a checklist, it's replaced with the contents of `/tmp/pr-checklist-${PR_NUMBER}.md`, otherwise a new checklist comment is added to the PR.

## Check Scripts

Each of the check scripts in this directory (which must start with a two digit number) can potentially add one or more checklist items to the PR checklist.  The scripts are run by `addPRChecklistIfNeeded.sh` in the order determined by sequence number in their names.  To re-order the checks, simply rename the files.

Each script is run with one or more of the following parameters...
* --repo: The respository to run against.  I.E. `asterisk/asterisk`.  None of the scripts use this parameter at present.
* --pr-number: The pull request number.  None of the scripts use this parameter at present.
* --pr-path: The path to the PR's json document.
* --pr-diff-path: The path to the PR's diff.
* --pr-commits-path: The path to the PR's "commits" json document.
* --pr-comments-path: The path to the PR's "comments" json document.
* --pr-checklist-path: The path to the checklist output markdown. Each check script may append one or more checklist items to this file.  If all of its checks pass, nothing is appended.

Although all the mentioned parameters are passed to every script by `addPRChecklistIfNeeded.sh`, not every script needs every parameter. The only parameter they all require is `--pr-checklist-path` because that's where the output needs to go. The scripts will throw errors if a parameter they do need is missing.

The text of the checklist item is hard coded in each script but simple to change.  Pay attention to how the output is formatted because it's critical to how the final checklist comment will appear.  To output a checklist item, a check script MUST pipe their checklist items into the `print_checklist_item` function.

The scripts all print debugging/progress information to /dev/stderr.

If you add new scripts, don't forget to make them executable before you commit.  Also be sure to update the documentation page at [Pull Request Checklist](https://docs.asterisk.org/Development/Policies-and-Procedures/Code-Contribution/Pull-Request-Checklist/).

## Testing

You can pass in the `--dry-run` option to `addPRChecklistIfNeeded.sh` to have it retrieve all the documents, run all the checks and output the resulting full checklist comment to stderr without modifying the PR itself.

Passing `--download-only` to `addPRChecklistIfNeeded.sh` will cause it to retrieve all the documents for the PR and exit.  You can examine the documents and reuse them.

Passing `--dont-download` to `addPRChecklistIfNeeded.sh` will cause it to NOT retrieve any documents for the PR and instead to re-use the ones previously retrieved using the `--download-only` option.

By downloading just the documents, you can test new check scripts by modifying the documents to simulate issues and seeing if the issue is correctly detected by the new script.

Because all data needed for the individual check scripts to do their jobs are in the files passed in as parameters, the check scripts themselves need no permissions or even network access and can be tested by simply running them directly with the appropriate documents. If you don't pass `--pr-checklist-path` option to a check script, it's output will automatically go to /dev/stderr.

You can dump the markdown of all of the checklist items without running the actual checks by running `./dump_all_checklist_items.sh`

## Adding Exceptions to a PR

If a checklist item on a PR is a false positive, for example, an alembic change that doesn't need a sample config change, you can add a comment to it that will cause the script to skip the check the next time it runs.

```
pr-checklist-exception: <check_name>
```

`<check_name>` is the name of the check script with the leading sequence number and dash removed as well as the `.sh` suffix.  For example:

```
pr-checklist-exception: cherry-picks
pr-checklist-exception: sample-configs
```

