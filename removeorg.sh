#!/bin/bash

NAME=""

. utils.sh

function printHelp() {
    echo "Usage: "
    echo "  removeorg.sh -n <org name>"
    echo "    -n <org name> - organisation name to remove"
    echo "  removeorg.sh -h (print this message)"
}

while getopts "hn:" opt; do
    case "$opt" in
        h)
            printHelp
            exit 0
            ;;
        n)
            NAME="$(generateSlug $OPTARG)"
            ;;
    esac
done

if [ "$NAME" == "" ]; then
    echo "No organisation name specified."
    echo
    printHelp
    exit 1
fi

askProceed

for dir in "ca.divvy.com/$NAME" "crypto-config/peerOrganizations/$NAME.divvy.com" "org-config/$NAME"; do
    echo "Removing $dir"
    rm -rf $dir
done

echo
echo "Done"
