#!/usr/bin/env bash

# This script performs the setup needed to create a Zettlr release package on
# Ubuntu Linux. The script is intended to be run using GitHub Hosted Runners,
# which use Ubuntu Linux. If not Ubuntu Linux, script exits with an error.
# The script is to be run as `root` user. If not, script exits with an error.
# The script is to be run from Zettlr's resources directory. If not, script
# exits with an error.
#
# This script performs the following setup steps:
# 1. Download package `libappindicator3-1` for both amd64 and arm64
# 2. Unpack package and copy libappindicator3-1.so into directory
#    `resources/usr/lib` ready for packaging. The binary libraries are included
#    in .zip and .AppImage release packages.

# LSB_RELEASE_FILE is used to determine the distribution's codename.
LSB_RELEASE_FILE=/etc/lsb-release
# PORT_SOURCES_FILE is used to set the sources for arm64 architecture
PORT_SOURCES_FILE=/etc/apt/sources.list.d/arm64-sources.list
# Number of times to retry apt commands. Sometimes apt fails due to internet
# errors
APT_RETIES=3

if [[ $EUID -ne 0 ]]; then
   echo "$0 must be run as root"
   exit 1
fi

if [[ ! -f "$LSB_RELEASE_FILE" ]]; then
    echo "$LSB_RELEASE_FILE does not exist. $0 must run on Ubuntu Linux."
    exit 1
fi

if [[ `basename $PWD` != "resources" ]]; then
    echo "$0 must run within the resources directory."
    exit 1
fi

# load $DISTRIB_CODENAME from the $LSB_RELEASE_FILE
. $LSB_RELEASE_FILE

if [[ -z "$DISTRIB_CODENAME" ]]; then
    echo "\$DISTRIB_CODENAME does not exist. $0 must run on Ubuntu Linux."
    exit 1
fi

# Setup $PORT_SOURCES_FILE. This is needed for `apt-get download` to work for
# other architectures other than the host's architecture
cat 2>/dev/null << EOF > $PORT_SOURCES_FILE
deb [arch=arm64] http://ports.ubuntu.com/ $DISTRIB_CODENAME main restricted
deb [arch=arm64] http://ports.ubuntu.com/ $DISTRIB_CODENAME-updates main restricted
deb [arch=arm64] http://ports.ubuntu.com/ $DISTRIB_CODENAME universe
deb [arch=arm64] http://ports.ubuntu.com/ $DISTRIB_CODENAME-updates universe
deb [arch=arm64] http://ports.ubuntu.com/ $DISTRIB_CODENAME multiverse
deb [arch=arm64] http://ports.ubuntu.com/ $DISTRIB_CODENAME-updates multiverse
deb [arch=arm64] http://ports.ubuntu.com/ $DISTRIB_CODENAME-backports main restricted universe multiverse
EOF
if [[ $? -ne 0 ]]; then
    echo "Unable to write to $PORT_SOURCES_FILE"
    exit $?
fi

# run: `apt-get update`. Try multiple times upto $APT_RETIES. Sometimes apt
# fails due to internet errors
count=1
while [[ $count -le $APT_RETIES ]]; do
    apt-get update
    return_code=$?
    if [[ $return_code -eq 0 ]]; then
        break
    fi
    ((count = count + 1))
done
if [[ $return_code -ne 0 ]]; then
    echo "Unable to run: apt-get update"
    exit $?
fi

# run: `apt-get download`. Try multiple times upto $APT_RETIES. Sometimes apt
# fails due to internet errors
# The following warning is displayed. The warning can be ignored, the download
# was successful:
#   W: Download is performed unsandboxed as root as file
#   'Zettlr/resources/libappindicator3-1_12.10.1+20.04.20200408.1-0ubuntu1_amd64.deb'
#   couldn't be accessed by user '_apt'. - pkgAcquire::Run (13: Permission denied)
count=1
while [[ $count -le $APT_RETIES ]]; do
    apt-get download libappindicator3-1:amd64 libappindicator3-1:arm64
    return_code=$?
    if [[ $return_code -eq 0 ]]; then
        break
    fi
    ((count = count + 1))
done
if [[ $return_code -ne 0 ]]; then
    echo "Unable to run: apt-get download"
    exit $?
fi

# unpack the .deb files
for file in *.deb; do
    dpkg -x $file .
    if [[ $? -ne 0 ]]; then
        echo "Unable to unpack $file"
        exit $?
    fi
done

# make libraries executable
find usr/lib -type f -name "*.so.*" -exec chmod a+x {} \;
if [[ $? -ne 0 ]]; then
    echo "Unable to change library permissions"
    exit $?
fi
