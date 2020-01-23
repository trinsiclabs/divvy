#!/bin/bash

NAME=""
CRYPTO_DIR=""
CONFIG_DIR=""
VOLUME_DIR=""

. utils.sh

function printHelp() {
    echo "Usage: "
    echo "  removeorg.sh -n <org name>"
    echo "    --name <org name> - organisation name to remove"
    echo "  removeorg.sh --help (print this message)"
}

POSITIONAL=()
while [[ $# -gt 0 ]]
do
    opt="$1"
    case "$opt" in
        --help)
            printHelp
            exit 0
            ;;
        --name)
            NAME="$(generateSlug $2)"
            MSP_NAME="${NAME}-msp"
            shift
            shift
            ;;
        *)
            POSITIONAL+=("$1")
            shift
            ;;
    esac
done
set -- "${POSITIONAL[@]}" # restore positional parameters

if [ "$NAME" == "" ]; then
    echo "No organisation name specified."
    echo
    printHelp
    exit 1
fi

askProceed

CRYPTO_DIR="crypto-config/peerOrganizations/$NAME.divvy.com"
CONFIG_DIR="org-config/$NAME"

# TODO: Delete channel

# TODO: Remove from consortium

echo "Stopping $NAME containers..."
docker-compose -f "$CONFIG_DIR/docker-compose.yaml" down --volumes
echo

echo "Removing config files..."
for dir in "$CA_DIR" "$CRYPTO_DIR" "$CONFIG_DIR"; do
    echo "Removing $dir"
    rm -rf $dir
done
echo

echo "Done"
