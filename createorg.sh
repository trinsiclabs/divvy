#!/bin/bash

NAME=""
MSP_NAME=""
CONFIG_DIR=""
PEER_PORT=7051

. utils.sh

function failAndExit() {
    echo $1

    for dir in $CONFIG_DIR; do
        if [ -d $dir ]; then
            rm -rf $dir
        fi
    done

    exit 1
}

function printHelp() {
    echo "Usage: "
    echo "  createorg.sh -n <org name> [-p <peer port>]"
    echo "    -n <org name> - organisation name to use"
    echo "    -p <peer port> - port the anchor peer listens on (defaults to 7051)"
    echo "  createorg.sh -h (print this message)"
}

function checkPrereqs() {
    for tool in cryptogen configtxgen; do
        which $tool > /dev/null 2>&1

        if [ "$?" -ne 0 ]; then
            echo "${tool} not found. Make sure the binaries have been added to your path."
            exit 1
        fi
    done
}

function generateCryptoConfig() {
    sed -e "s/\${NAME}/$1/g" ./templates/crypto-config.yaml
}

function generateCaConfig() {
    sed -e "s/\${NAME}/$1/g" ./templates/ca-config.yaml
}

function generateCryptoMaterial() {
    cryptogen generate --config=$1

    if [ $? -ne 0 ]; then
        failAndExit "Failed to generate certificates..."
    fi
}

function replacePrivateKey() {
    ARCH=$(uname -s | grep Darwin)

    if [ "$ARCH" == "Darwin" ]; then
        OPTS="-it"
    else
        OPTS="-i"
    fi

    CURRENT_DIR=$PWD

    cd "crypto-config/peerOrganizations/$1.divvy.com/ca/"
    PRIV_KEY=$(ls *_sk)

    cd "$CURRENT_DIR"
    sed $OPTS "s/\${PRIV_KEY}/$PRIV_KEY/g" "./ca.divvy.com/ca/$1/ca-config.yaml"
}

function generateNetworkConfig() {
    sed -e "s/\${NAME}/$1/g" \
        -e "s/\${MSP_NAME}/$2/g" \
        -e "s/\${PEER_PORT}/$3/g" \
        ./templates/configtx.yaml
}

function generateOrgDefinition() {
    configtxgen -configPath $1 -printOrg $2
}

function oneLinePem {
    echo "`awk 'NF {sub(/\\n/, ""); printf "%s\\\\\\\n",$0;}' $1`"
}

function generateConnectionProfile {
    local PP=$(oneLinePem "crypto-config/peerOrganizations/$1.divvy.com/tlsca/tlsca.$1.divvy.com-cert.pem")
    local CP=$(oneLinePem "crypto-config/peerOrganizations/$1.divvy.com/ca/ca.$1.divvy.com-cert.pem")

    sed -e "s/\${NAME}/$1/" \
        -e "s/\${MSP_NAME}/$2/" \
        -e "s/\${PEER_PORT}/$3/" \
        -e "s#\${PEER_PEM}#$PP#" \
        -e "s#\${CA_PEM}#$CP#" \
        ./templates/connection-profile.yaml | sed -e $'s/\\\\n/\\\n        /g'
}

function generateDockerCompose() {
    sed -e "s/\${NAME}/$1/g" \
        -e "s/\${MSP_NAME}/$2/g" \
        -e "s/\${PEER_PORT}/$3/g" \
        ./templates/docker-compose.yaml
}

checkPrereqs

while getopts "hn:" opt; do
    case "$opt" in
        h)
            printHelp
            exit 0
            ;;
        n)
            NAME="$(generateSlug $OPTARG)"
            MSP_NAME="${NAME}-msp"
            ;;
        p)
            PEER_PORT=$OPTARG
            ;;
    esac
done

if [ "$NAME" == "" ]; then
    echo "No organisation name specified."
    echo
    printHelp
    exit 1
fi

CONFIG_DIR="$PWD/org-config/$NAME"

if [ -d $CONFIG_DIR ]; then
    echo "There is already an organisation called ${NAME}."
    exit 1
fi

askProceed

mkdir -p $CONFIG_DIR

echo "Generating CA config..."
mkdir -p "./ca.divvy.com/ca/$NAME"
generateCaConfig $NAME > "./ca.divvy.com/ca/$NAME/ca-config.yaml"
echo

echo "Generating crypto config for ${NAME}..."
generateCryptoConfig $NAME > "$CONFIG_DIR/crypto-config.yaml"
echo

echo "Generating certificates for trust domain:"
generateCryptoMaterial "$CONFIG_DIR/crypto-config.yaml"
echo

echo "Update crypto config with private key..."
replacePrivateKey $NAME
echo

echo "Generating network config..."
generateNetworkConfig $NAME $MSP_NAME $PEER_PORT > "$CONFIG_DIR/configtx.yaml"
echo

echo "Generating org definition..."
generateOrgDefinition $CONFIG_DIR $MSP_NAME > "$CONFIG_DIR/${NAME}.json"
echo

echo "Generating connection profile..."
generateConnectionProfile $NAME $MSP_NAME $PEER_PORT > "$CONFIG_DIR/connection-profile.yaml"
echo

echo "Generating docker compose file..."
generateDockerCompose $NAME $MSP_NAME $PEER_PORT  > "$CONFIG_DIR/docker-compose.yaml"
echo

echo "Done"
