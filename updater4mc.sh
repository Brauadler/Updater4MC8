#!/bin/bash
#
#   Mailcleaner Updater - Updater for MailCleaner Antispam
#   Copyright (C) 2017 Florian Billebault <florian.billebault@gmail.com>
#
#   This program is free software; you can redistribute it and/or modify
#   it under the terms of the GNU General Public License as published by
#   the Free Software Foundation; either version 3 of the License, or
#   (at your option) any later version.
#
#   This program is distributed in the hope that it will be useful,
#   but WITHOUT ANY WARRANTY; without even the implied warranty of
#   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#   GNU General Public License for more details.
#
#   You should have received a copy of the GNU General Public License
#   along with this program. If not, see <http://www.gnu.org/licenses/>.
#
#
#   This script allow to update MailCleaner from an external source
#
#   Usage:
#           ./updater4mc.sh [--noreboot]
#

CONFFILE=/etc/mailcleaner.conf
STATUSFILE=/var/mailcleaner/spool/mailcleaner/updater4mc.status

if [ ! -f "$CONFFILE" ]; then 
  echo "Not a valid MailCleaner Installation: no conf file"
  echo "Not a valid MailCleaner Installation: no conf file" > $STATUSFILE
  exit 1
fi

HOSTID=`grep 'HOSTID' $CONFFILE | cut -d ' ' -f3`
if [ "$HOSTID" = "" ]; then
  HOSTID=1
fi

SRCDIR=`grep 'SRCDIR' $CONFFILE | cut -d ' ' -f3`
if [ "$SRCDIR" = "" ]; then
  SRCDIR="/opt/mailcleaner"
fi
VARDIR=`grep 'VARDIR' $CONFFILE | cut -d ' ' -f3`
if [ "$VARDIR" = "" ]; then
  VARDIR="/opt/mailcleaner"
fi

ISMASTER=$(grep 'ISMASTER' ${CONFFILE} | cut -d ' ' -f3)

HTTPPROXY=`grep -e '^HTTPPROXY' $CONFFILE | cut -d ' ' -f3`
export http_proxy=$HTTPPROXY


function realpath()
{
    local __rpath=$1
    shift
    local f=$@

    if [ -d "$f" ]; then
	base=""
	dir="$f"
    else
	base="/$(basename "$f")"
	dir=$(dirname "$f")
    fi
    dir=$(cd "$dir" && /bin/pwd)
    eval $__rpath="'$dir'"
}

realpath rpath "$0"

# Enabling copy output and error to logs
exec > >(tee -ai "${VARDIR}/log/mailcleaner/updater4mc.log")
exec 2>&1

echo "Running" > $STATUSFILE
echo "$(date +%F_%T) Launching Updater4MC"

cd "$rpath"
git fetch && BRANCH=`git status | grep 'On branch' | sed -r 's/On branch //'`
if [ "$BRANCH" != 'master' ]; then
	echo "Abandoning update because Git tree at '$rpath' is not on 'master' branch."
	exit 1
fi

git reset --hard @{u} && STATUS=`git pull`
if [ "$STATUS" != 'Already up-to-date.' ]; then
	echo "Abandoning update because Git tree at '$rpath' is blocking changes"
	exit 1
fi

cd "${SRCDIR}"
SRCSTART=$(git log --no-merges --decorate=no -n 1 | head -n 1 | cut -d' ' -f2)
${SRCDIR}/lib/updates/gitupdate.sh
BRANCH=`git status | grep 'On branch' | sed -r 's/On branch //'`
if [ "$BRANCH" != 'master' ]; then
	echo "Abandoning update because Git tree at '$SRCDIR' is not on 'master' branch."
	exit 1
fi
# Clean up files that have been removed
for i in $(git status | grep 'deleted by us:' | cut -d: -f 2); do
	git rm $i
done
STATUS=`git pull`
# Unless there were no changes
if [ "$STATUS" != 'Already up-to-date.' ]; then
	STATUS=`git status | head -n 2 | tail -n 1`
	# Unless those changes were successfully applied
	if [ "$STATUS" != "Your branch is up-to-date with 'origin/master'." ]; then
		echo "Abandoning update because Git tree at '$SRCDIR' is blocking changes"
		exit 1
	fi
fi
SRCEND=$(git log --no-merges --decorate=no -n 1 | head -n 1 | cut -d' ' -f2)

[ ! -d "${VARDIR}/spool/updater" ] && mkdir "${VARDIR}/spool/updater"

for updtlib in $(find $rpath"/libs" -type f -name "*.lib" |sort |uniq)
do
    echo -n "Importing library: $updtlib ..."
    . "$updtlib"
    echo "Done."
done

UPDATED=0
VERSION=0
for updtfile in $(find $rpath"/updates/" -type f -name "*.update" |sort |uniq)
do
    if [ ! -e "${VARDIR}/spool/updater/$(basename -s'.update' ${updtfile})" ]; then
	echo "Executing update: $updtfile ..."
	. "$updtfile"
	retcode=$?
	if [ $retcode -eq 0 ]; then
	    touch "${VARDIR}/spool/updater/$(basename -s'.update' ${updtfile})"
            UPDATED=1
            VERSION=`echo $updtfile | sed 's/^.*\/\([0-9]*\)_[^\/]*$/\1/'`
	elif [ $retcode -ne 1 ]; then
	    echo -e "\tError during ${updtfile} update. Please join logfile to your post on MailCleaner Community forum."
            echo "Failed to complete update $updtfile" > $STATUSFILE
	    exit 1
	fi
	echo "End of update."
    else
        VERSION=`echo $updtfile | sed 's/^.*\/\([0-9]*\)_[^\/]*$/\1/'`
	echo "Already updated: $updtfile ..."
    fi
done

if [[ $SRCSTART != $SRCEND ]] || [[ $UPDATED == 1 ]]; then
    . "${rpath}/updates/tolaunch.always" $1
fi

# Prepend version with 1. We'll be skipping 93-99 for convenience. All versions in Updater4MC8 legacy repository will be > 100.
echo $(echo 1$VERSION)-$(echo ${SRCEND} | cut -b-7) > ${SRCDIR}/etc/mailcleaner/version.def

echo
echo "$(date +%F_%T) End of Updater4MC:"
echo ">> All updates done ! Follow forum announces or relaunch this script regularly."
echo ">> Logfile present here: ${VARDIR}/log/mailcleaner/updater4mc.log"
echo

rm $STATUSFILE
${SRCDIR}/scripts/cron/service_checks.pl
exit 0
