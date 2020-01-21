#!/bin/bash

NAME=""
MSP_NAME=""
CONFIG_DIR=""
PEER_PORT=7051
CA_PORT=7054

. utils.sh

function printHelp() {
    echo "Usage: "
    echo "  createorg.sh --name <org name> [--peerport <peer port>] [--caport <ca port>]"
    echo "    --name <org name> - organisation name to use"
    echo "    --peerport <peer port> - port the anchor peer listens on (defaults to 7051)"
    echo "    --caport <ca port> - port the Orgs CA listens on (defaults to 7054)"
    echo "  createorg.sh --help (print this message)"
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
        -e "s/\${CA_PORT}/$4/" \
        -e "s#\${PEER_PEM}#$PP#" \
        -e "s#\${CA_PEM}#$CP#" \
        ./templates/connection-profile.yaml | sed -e $'s/\\\\n/\\\n        /g'
}

function generateDockerCompose() {
    local CURRENT_DIR=$PWD

    cd "crypto-config/peerOrganizations/$1.divvy.com/ca/"
    local PRIV_KEY=$(ls *_sk)

    cd "$CURRENT_DIR"

    sed -e "s/\${NAME}/$1/g" \
        -e "s/\${MSP_NAME}/$2/g" \
        -e "s/\${PEER_PORT}/$3/g" \
        -e "s/\${CA_PORT}/$4/g" \
        -e "s/\${PRIV_KEY}/$PRIV_KEY/g" \
        ./templates/docker-compose.yaml
}

function addOrgToConsortium() {
    local $ORG_DEF="./org-config/$1/$1.json"
    local $CONF_BLOCK="./config-$1.pb"
    local $CONF_MOD_BLOCK="./config-modified-$1.pb"
    local $CONF_DELTA_BLOCK="./config-delta-$1.pb"
    local $CONF_JSON="./config-$1.json"
    local $CONF_MOD_JSON="./config-modified-$1.json"
    local $CONF_DELTA_JSON="./config-delta-$1.json"
    local $PAYLOAD_BLOCK="./payload-$1.pb"
    local $PAYLOAD_JSON="./payload-$1.json"

    # Get the latest config block from the sys-channel.
    docker exec cli.divvy.com peer channel fetch config $CONF_BLOCK -o orderer.divvy.com:7050 -c sys-channel

    # Convert the block to JSON so we can modify it.
    docker exec cli.divvy.com configtxlator proto_decode --input $CONF_BLOCK --type common.Block | jq .data.data[0].payload.data.config > $CONF_JSON

    # Add the Org definition to config.
    docker exec cli.divvy.com jq -s --arg MSP_NAME "$2"'.[0] * {"channel_group":{"groups":{"Consortiums":{"groups": {"Default": {"groups": {"$MSP_NAME":.[1]}, "mod_policy": "/Channel/Orderer/Admins", "policies": {}, "values": {"ChannelCreationPolicy": {"mod_policy": "/Channel/Orderer/Admins","value": {"type": 3,"value": {"rule": "ANY","sub_policy": "Admins"}},"version": "0"}},"version": "0"}}}}}}' $CONF_JSON $ORG_DEF > $CONF_MOD_JSON

    # Convert the original config JSON to a block.
    docker exec cli.divvy.com configtxlator proto_encode --input $CONF_JSON --type common.Config --output $CONF_BLOCK

    # Convert the modified config JSON to a block.
    docker exec cli.divvy.com configtxlator proto_encode --input $CONF_MOD_JSON --type common.Config --output $CONF_MOD_BLOCK

    # Generate a delta.
    docker exec cli.divvy.com configtxlator compute_update --channel_id sys-channel --original $CONF_BLOCK --updated $CONF_MOD_BLOCK --output $CONF_DELTA_BLOCK

    # Convert the delta to JSON so we can add a header.
    docker exec cli.divvy.com configtxlator proto_decode --input $CONF_DELTA_BLOCK --type common.ConfigUpdate | jq . > $CONF_DELTA_JSON

    # Add the header.
    docker exec cli.divvy.com echo '{"payload":{"header":{"channel_header":{"channel_id":"sys-channel", "type":2}},"data":{"config_update":'$(cat $CONF_DELTA_JSON)'}}}' | jq . > $PAYLOAD_JSON

    # Convert the payload to a block.
    docker exec cli.divvy.com configtxlator proto_encode --input $PAYLOAD_JSON --type common.Envelope --output $PAYLOAD_BLOCK

    # # Make the update.
    # docker exec cli.divvy.com peer channel update -f $PAYLOAD_BLOCK -c sys-channel -o orderer.divvy.com:7050

    # # Clean up.
    # for file in $ORG_DEF $CONF_BLOCK $CONF_MOD_BLOCK $CONF_DELTA_BLOCK $CONF_JSON $CONF_MOD_JSON $CONF_DELTA_JSON $PAYLOAD_BLOCK $PAYLOAD_JSON; do
    #     rm $file
    # done
}

checkPrereqs

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
        --peerport)
            PEER_PORT=$2
            shift
            shift
            ;;
        --caport)
            CA_PORT=$2
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

CONFIG_DIR="$PWD/org-config/$NAME"

if [ -d $CONFIG_DIR ]; then
    echo "There is already an organisation called ${NAME}."
    exit 1
fi

askProceed

mkdir -p $CONFIG_DIR

echo "Generating crypto config for ${NAME}..."
generateCryptoConfig $NAME > "$CONFIG_DIR/crypto-config.yaml"
echo

echo "Generating certificates for trust domain:"
generateCryptoMaterial "$CONFIG_DIR/crypto-config.yaml"
echo

echo "Generating network config..."
generateNetworkConfig $NAME $MSP_NAME $PEER_PORT > "$CONFIG_DIR/configtx.yaml"
echo

echo "Generating org definition..."
generateOrgDefinition $CONFIG_DIR $MSP_NAME > "$CONFIG_DIR/${NAME}.json"
echo

echo "Generating connection profile..."
generateConnectionProfile $NAME $MSP_NAME $PEER_PORT $CA_PORT > "$CONFIG_DIR/connection-profile.yaml"
echo

echo "Generating docker compose file..."
generateDockerCompose $NAME $MSP_NAME $PEER_PORT $CA_PORT > "$CONFIG_DIR/docker-compose.yaml"
echo

echo "Adding $NAME to the default consortium..."
addOrgToConsortium $NAME $MSP_NAME
echo

# echo "Starting Organisation containers..."
# docker-compose -f "$CONFIG_DIR/docker-compose.yaml" up -d 2>&1
# sleep 10

# if [ $? -ne 0 ]; then
#     echo "Unable to add Organisation to  network"
#     exit 1
# fi

# docker ps -a

echo "Done"
