# aptlytools

This repository contains tools for working with [aptly](https://www.aptly.info/), a Debian repository management tool. The scripts are designed to help search and synchronize packages within aptly snapshots.

## Scripts

### aptlysearch.sh
Search for packages within aptly snapshots.

**Note:** Only trailing wildcards (e.g., nginx*) are supported. Patterns like *nginx or *nginx* are not allowed.

#### Usage
```
sudo ./aptlysearch.sh <packagename or pattern>
```
- **Exact match:**
  ```
  sudo ./aptlysearch.sh nginx
  ```
- **Wildcard match (prefix only):**
  ```
  sudo ./aptlysearch.sh nginx*
  ```

#### Description
- Must be run as root.
- Searches all aptly snapshots for packages matching the given name or pattern.
- Supports wildcard (`*`) for pattern matching.
- Prints matching packages and the snapshot(s) they are found in.
- Exits with code 0 if found, 1 if not found.

### aptlysync.sh
Synchronize repositories, create snapshots, merge, publish, clean up, and send notifications.

#### Usage
```
sudo ./aptlysync.sh [-r <repo1,repo2,...>] [-m <email1,email2,...>] [-q] [-d]
```

**Options:**
- `-r` : Comma-separated list of repositories to sync (default: all mirrors).
- `-m` : Comma-separated list of emails for notifications (default: configured MAILREC).
- `-q` : Quiet mode (logs only, minimal console output).
- `-d` : Dry-run mode (no changes made, only logs actions).

#### Features
- Must be run as root.
- Syncs specified or all aptly mirrors.
- Creates snapshots for updated mirrors.
- Merges last two snapshots for selected repos (see MERGE variable in script).
- Publishes latest snapshot for each repo.
- Cleans up old snapshots, keeping only the most recent (configurable).
- Sends email notifications about updates and errors.
- Logs all actions to aptly log directory.

#### Workflow
1. Sync mirrors and check for updates.
2. If updates found, create a new snapshot.
3. Optionally merge snapshots for configured repos.
4. Publish the latest snapshot.
5. Delete older snapshots, keeping only the most recent N.
6. Send notification emails with update details.

## Requirements
- Debian 11 (Bullseye) or compatible
- aptly 1.4.0 or newer
- Bash shell

## Author
M. Chudnovsky
