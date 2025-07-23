#!/bin/bash
# Written by M.Chudnovsky
# tested on Debian 11 (Bullseye) with aptly 1.4.0
# This script is used to sync repositories with aptly, create snapshots, merge snapshots, publish, clean up old snapshots, and send email notifications.

# Main workflow:
# 1. Parse command-line options for repositories, email recipients, quiet/dry-run modes.
# 2. For each repository:
#    a. Update the mirror and check for new packages.
#    b. If updates found, create a new snapshot.
#    c. If repo is in MERGE list, merge last two snapshots.
#    d. Publish the latest snapshot.
#    e. Clean up old snapshots, keeping only the most recent N.
#    f. Log actions and send notification emails.
# 3. If no repository list is provided, sync all mirrors found in aptly.
#
# Key variables:
# - MAILREC: Email recipients for notifications.
# - ADMIN: Email for error notifications.
# - GPG: GPG key for publishing.
# - MERGE: List of repos to merge snapshots for.
# - SNAPSHOT_KEEP: Number of snapshots to keep per repo.


############################################################
# Ensure script is run as root
############################################################
if [ "$(id -u)" != "0" ]; then
    echo "This script must be run as root" 1>&2
    exit 1
fi

############################################################
# Configuration variables
############################################################
MAILREC="someone@somewhere.com"   # Email recipients for notifications
ADMIN="someone@somewhere.com"   # Admin email for error notifications
GPG='7A26Dxxxxxxxxxxxxxxxx729E2' # GPG key name for publishing
MERGE="sury-bullseye"             # Repos to merge snapshots for
SNAPSHOT_KEEP=5                    # Number of snapshots to keep per repo

############################################################
# Initialization
############################################################
APPBASE=$(aptly config show | awk -F\" '/rootDir/{print $4}') # Aptly root directory
APPNAME=$(basename $0)                                      # Script name
MAILFILE=${APPBASE}/aptlysync.mail.tmp                      # Temp mail file for notifications
rm -f ${MAILFILE}                                           # Remove old mail file
[ ! -d ${APPBASE}/log ] && mkdir -p ${APPBASE}/log          # Ensure log directory exists
TS=$(date "+%Y%m%d-%H:%M:%S")                             # Timestamp for logs/snapshots
QUIET=0                                                     # Quiet mode flag
DRYRUN=0                                                    # Dry-run mode flag
rm -rf /tmp/aptly* ${MAILFILE}                              # Clean up temp files

############################################################
# usage: Print usage information and exit
############################################################
usage(){
    echo "${APPNAME} $1"
    echo -e "Usage:"
    echo -e "-r\t-r <Comma separated list of repositories to sync>"
    echo -e "-m\t-m <Comma separated list of emails to send email notification to>"
    echo -e "-q\tquiet"
    echo -e "-d\tdry-run mode (no changes made, only logs actions)"
    exit 1
}

while getopts ":m:r:qd" o; do
    case "${o}" in
        q)
            QUIET=1         # Enable quiet mode
            ;;
        d)
            DRYRUN=1        # Enable dry-run mode
            ;;
        r)
            REPOLIST=${OPTARG} # Set repository list
            ;;
        m)
            MAILREC=${OPTARG}  # Set mail recipients
            ;;
        *)
            usage           # Show usage for invalid option
            ;;
    esac
done
shift $((OPTIND-1))         # Shift processed options

############################################################
# out: Output/log helper function
# Usage: out "message" [m]
# If QUIET=0, prints and logs; if QUIET=1, logs only.
# If second argument is 'm', also appends to mail file.
############################################################
out(){
    if [ $QUIET -ne 1 ]; then
        echo "$1" | tee -a ${APPBASE}/log/aptlysync.log
    else
        echo "$1" >> ${APPBASE}/log/aptlysync.log
    fi
    [ "$2" = "m" ] && echo "$1" >> ${MAILFILE}
}

############################################################
# syncrepo: Sync a single repository
# - Updates mirror and checks for new packages
# - Creates snapshot if updates found
# - Merges last two snapshots if repo is in MERGE list
# - Publishes latest snapshot
# - Cleans up old snapshots
# - Logs actions and sends notifications
############################################################
syncrepo(){
    if [ $DRYRUN -eq 1 ]; then
        out "$TS [DRY-RUN] Would update mirror $1" m  # Log dry-run update
        out "$TS [DRY-RUN] No real update performed for $1, skipping snapshot creation."  # Log dry-run skip
        return 0
    fi

    TMPLOG=$(/usr/bin/aptly mirror update $1 2>&1)  # Update mirror and capture output
    (($? != 0)) && { echo -e "$TS - Error! Aptly mirror failed for $1\n$TMPLOG" | mailx -s "Aptly Sync New package updates - ERROR" $ADMIN; exit 1; }  # Error if update fails

    out "$(echo "$TMPLOG" | awk '{print TS,$0}' TS="$TS")"  # Log update output

    UPDATED=$(echo "$TMPLOG" | grep Success | awk -F/ '/pool/{print $NF}')  # Find updated packages
    if [ "$UPDATED" != "" ]; then
        SNAP="${1}-${TS}"  # Name new snapshot
        echo "$UPDATED" | awk '{print TS,$0}' TS="$TS" >> ${APPBASE}/log/aptlysync-updates-${1}.log  # Log updated packages
        echo -e "Updated packages for repository: $1\n\n$UPDATED\n" >> ${MAILFILE}  # Add to mail file

        echo -e "Created snapshot ${SNAP}" >> ${MAILFILE}  # Log snapshot creation
        OUT=$(aptly snapshot create ${SNAP} from mirror $1)  # Create snapshot
        (($? != 0)) && {
            echo "$OUT" | ts >> ${APPBASE}/log/aptlysync-updates-${1}.log  # Log error output
            echo -e "$TS - Error! Aptly snapshot $SNAP failed for repository $1\n$OUT" | mailx -s "Aptly Sync New package updates - ERROR" $ADMIN
            exit 1
        }

        for repo in $MERGE; do  # Check if repo needs merging
            if [ "$1" = "$repo" ]; then
                LAST2SNAP=$(aptly snapshot list | awk -v repo="$repo" -F'[][]' '$0 ~ "\\[" repo "-[0-9]" {print $2}' | sort | tail -n 2 | xargs)  # Get last 2 snapshots
                if [ -z "$LAST2SNAP" ] || [ $(echo "$LAST2SNAP" | wc -w) -ne 2 ]; then
                    out "$TS Error: Could not find two snapshots to merge for $repo. Skipping merge." m  # Log merge skip
                else
                    NEWSNAP="${repo}-$(date "+%Y%m%d-%H%M%S")"  # Name merged snapshot
                    echo -e "Merging snapshots: $LAST2SNAP" >> "$MAILFILE"  # Log merge
                    OUT=$(aptly snapshot merge -latest=false -no-remove "$NEWSNAP" $LAST2SNAP 2>&1)  # Merge snapshots
                    if [ $? -ne 0 ]; then
                        echo "$OUT" | ts >> "${APPBASE}/log/aptlysync-updates-${1}.log"  # Log error output
                        echo -e "$TS - Error! Aptly failed to merge snapshots: $LAST2SNAP\n$OUT" | mailx -s "Aptly Sync New package updates - ERROR" "$ADMIN"
                        exit 1
                    fi
                    SNAP="$NEWSNAP"  # Use merged snapshot for publishing
                fi
            fi
        done

        echo -e "Serving snapshot ${SNAP}" >> "$MAILFILE"  # Log publish
        OUT=$(aptly publish switch -gpg-key="$GPG" "$1" "$SNAP" 2>&1)  # Publish snapshot
        if [ $? -ne 0 ]; then
            echo "$OUT" | ts >> "${APPBASE}/log/aptlysync-updates-${1}.log"  # Log error output
            echo -e "$TS - Error! Aptly snapshot publishing failed: $SNAP to $1\n$TMPLOG\nMost likely wrong name for the repository, snapshot name has to be repository_name-timestamp" | mailx -s "Aptly Sync New package updates - ERROR" "$ADMIN"
            exit 1
        fi
    else
        out "$TS Repository \`$1\` no new packages or updates found."  # Log no updates
    fi

    KEEP=$SNAPSHOT_KEEP  # Number of snapshots to keep
    OLD_SNAPSHOTS=$(aptly snapshot list | grep '\['$1'-[0-9]' | awk -F[ '{print $2}' | awk -F] '{print $1}' | head -n -$KEEP)  # Find old snapshots
    for SNAP in $OLD_SNAPSHOTS; do
      out "$TS Deleting old snapshot $SNAP" m  # Log deletion
      if [ $DRYRUN -eq 0 ]; then
        OUT=$(aptly snapshot drop -force $SNAP 2>&1)  # Delete snapshot
        if [ $? -ne 0 ]; then
          echo -e "$TS - Error! Failed to delete snapshot $SNAP\n$OUT" | mailx -s "Aptly Snapshot Cleanup - ERROR" $ADMIN
          out "$TS Failed to delete snapshot $SNAP" m  # Log error
        fi
      else
        out "$TS [DRY-RUN] Would delete snapshot $SNAP" m  # Log dry-run deletion
      fi
    done

    echo "" >> ${APPBASE}/log/aptlysync.log  # Add blank line to log
}

[ "${MAILREC}" = "" ] && out "$TS No MAILREC variable set.  Nobody will be notified about new updates."
    # Warn if mail variables are not set
[ "${ADMIN}" = "" ] && out "$TS No ADMIN variable set.  Nobody will be notified about errors."

if [ "$REPOLIST" != "" ]; then
    REPOLIST=$(echo "$REPOLIST" | sed 's/,/ /g') # Convert comma-separated to space-separated
else
    OUT=$(aptly mirror list) # Get all mirrors if no list provided
    (($? != 0)) && { echo -e "$TS - Error! Could not get list of mirrors from aptly!\n$OUT" | mailx -s "Aptly Sync New package updates - ERROR" $ADMIN; exit 1; }
    REPOLIST=$(echo "$OUT" | awk -F[ '{print $2}' | awk -F] '$1!=""{printf("%s ",$1)}END{print}')
    out "$TS No list of mirrors provided.  got list of mirrors from aptly instead: $REPOLIST"
fi

# Sync each repository in the list
for id in ${REPOLIST}; do syncrepo "$id"; done

# Send notification email if mail file exists and recipients are set
[ -r "$MAILFILE" ] && [ -n "$MAILREC" ] && cat "$MAILFILE" | mailx -r "Admin" -s "Aptly Sync New package updates" "$MAILREC"
