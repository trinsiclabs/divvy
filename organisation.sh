#!/bin/bash

ORG=""
PEER_PORT=""
CA_PORT=""
CHANNEL=""

MSP_NAME=""
CONFIG_DIR=""
VOLUME_DIR=""

. utils.sh

export PATH=$PWD/bin:$PATH

# Print the usage message
function printHelp() {
    echo "Usage: "
    echo "  organisation.sh <mode> --org <org name> [--peerport <port>] [--caport <port>] [--channel <channel>]"
    echo "    <mode> - one of 'create', 'remove', or 'joinchannel'"
    echo "      - 'create' - bring up the network with docker-compose up"
    echo "      - 'remove' - clear the network with docker-compose down"
    echo "      - 'joinchannel' - restart the network"
    echo "    --org <org name> - name of the Org to use"
    echo "    --peerport <port> - port the Org peer listens on"
    echo "    --caport <port> - port the Org CA listens on"
    echo "    --channel <channel> - name of the channel to join"
    echo "  organisation.sh --help (print this message)"
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
    sed -e "s/\${ORG}/$1/g" ./templates/crypto-config.yaml
}

function generateNetworkConfig() {
    sed -e "s/\${ORG}/$1/g" \
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

    sed -e "s/\${ORG}/$1/" \
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

    sed -e "s/\${ORG}/$1/g" \
        -e "s/\${MSP_NAME}/$2/g" \
        -e "s/\${PEER_PORT}/$3/g" \
        -e "s/\${CA_PORT}/$4/g" \
        -e "s/\${PRIV_KEY}/$PRIV_KEY/g" \
        ./templates/docker-compose.yaml
}

function addOrgToConsortium() {
    local OUT_DIR="./org-creation/$1"
    local ORG_DEF="./org-config/$1/$1.json"
    local CONF_BLOCK="$OUT_DIR/config-$1.pb"
    local CONF_MOD_BLOCK="$OUT_DIR/config-modified-$1.pb"
    local CONF_DELTA_BLOCK="$OUT_DIR/config-delta-$1.pb"
    local CONF_JSON="$OUT_DIR/config-$1.json"
    local CONF_MOD_JSON="$OUT_DIR/config-modified-$1.json"
    local CONF_DELTA_JSON="$OUT_DIR/config-delta-$1.json"
    local PAYLOAD_BLOCK="$OUT_DIR/payload-$1.pb"
    local PAYLOAD_JSON="$OUT_DIR/payload-$1.json"

    # Create an output directory for the config files we're about to generate.
    docker exec cli.divvy.com mkdir -p $OUT_DIR

    if [ $? -ne 0 ]; then
        exit 1
    fi

    # Get the latest config block from the sys-channel.
    docker exec cli.divvy.com peer channel fetch config $CONF_BLOCK -o orderer.divvy.com:7050 -c sys-channel

    if [ $? -ne 0 ]; then
        exit 1
    fi

    # Convert the block to JSON so we can modify it.
    docker exec -i \
        -e CONF_BLOCK=$CONF_BLOCK \
        -e CONF_JSON=$CONF_JSON \
        cli.divvy.com bash <<EOF
        configtxlator proto_decode --input $CONF_BLOCK --type common.Block | jq .data.data[0].payload.data.config > $CONF_JSON
EOF

    if [ $? -ne 0 ]; then
        exit 1
    fi

    # Add the Org definition to config.
    docker exec -i \
        -e MSP_NAME=$2 \
        -e CONF_JSON=$CONF_JSON \
        -e ORG_DEF=$ORG_DEF \
        -e CONF_MOD_JSON=$CONF_MOD_JSON \
        cli.divvy.com bash <<EOF
        jq -s --arg MSP_NAME "$MSP_NAME" '.[0] * {"channel_group":{"groups":{"Consortiums":{"groups": {"Default": {"groups": {"$MSP_NAME":.[1]}, "mod_policy": "/Channel/Orderer/Admins", "policies": {}, "values": {"ChannelCreationPolicy": {"mod_policy": "/Channel/Orderer/Admins","value": {"type": 3,"value": {"rule": "ANY","sub_policy": "Admins"}},"version": "0"}},"version": "0"}}}}}}' $CONF_JSON $ORG_DEF > $CONF_MOD_JSON
EOF

    if [ $? -ne 0 ]; then
        exit 1
    fi

    # Convert the original (extracted section) config JSON back to a block.
    docker exec cli.divvy.com configtxlator proto_encode \
        --input $CONF_JSON \
        --type common.Config \
        --output $CONF_BLOCK

    if [ $? -ne 0 ]; then
        exit 1
    fi

    # Convert the modified config JSON to a block.
    docker exec cli.divvy.com configtxlator proto_encode \
        --input $CONF_MOD_JSON \
        --type common.Config \
        --output $CONF_MOD_BLOCK

    if [ $? -ne 0 ]; then
        exit 1
    fi

    # Generate a delta.
    docker exec cli.divvy.com configtxlator compute_update \
        --channel_id sys-channel \
        --original $CONF_BLOCK \
        --updated $CONF_MOD_BLOCK \
        --output $CONF_DELTA_BLOCK

    if [ $? -ne 0 ]; then
        exit 1
    fi

    # Convert the delta to JSON so we can add a header.
    docker exec -i \
        -e CONF_DELTA_BLOCK=$CONF_DELTA_BLOCK \
        -e CONF_DELTA_JSON=$CONF_DELTA_JSON \
        cli.divvy.com bash <<EOF
        configtxlator proto_decode --input $CONF_DELTA_BLOCK --type common.ConfigUpdate | jq . > $CONF_DELTA_JSON
EOF

    if [ $? -ne 0 ]; then
        exit 1
    fi

    # Add the header.
    docker exec -i \
        -e CONF_DELTA_JSON=$CONF_DELTA_JSON \
        -e PAYLOAD_JSON=$PAYLOAD_JSON \
        cli.divvy.com bash -c 'DELTA=$(< $CONF_DELTA_JSON); echo \''{\""payload\"":{\""header\"":{\""channel_header\"":{\""channel_id\"":\""sys-channel\"", \""type\"":2}},\""data\"":{\""config_update\"":$DELTA}}}\'' jq . > $PAYLOAD_JSON'

    if [ $? -ne 0 ]; then
        exit 1
    fi

    # Convert the payload to a block.
    docker exec cli.divvy.com configtxlator proto_encode \
        --input $PAYLOAD_JSON \
        --type common.Envelope \
        --output $PAYLOAD_BLOCK

    if [ $? -ne 0 ]; then
        exit 1
    fi

    # Make the update.
    docker exec cli.divvy.com peer channel update -f $PAYLOAD_BLOCK -c sys-channel -o orderer.divvy.com:7050

    if [ $? -ne 0 ]; then
        exit 1
    fi

    # Clean up.
    docker exec cli.divvy.com rm -rf $OUT_DIR

    if [ $? -ne 0 ]; then
        exit 1
    fi
}

function createOrgChannel() {
    local CHANNEL_ID="$2-channel"
    local CONTAINER="peer.$2.divvy.com"

    echo "Generating config transactions..."

    # Generate the channel configuration transation.
    configtxgen \
        -configPath $1 \
        -profile $CHANNEL_ID \
        -outputCreateChannelTx "$1/channel.tx" \
        -channelID $CHANNEL_ID

    # Generate the anchor peer transaction.
    configtxgen \
        -configPath $1 \
        -profile $CHANNEL_ID \
        -outputAnchorPeersUpdate "$1/$2-msp-anchor-$2-channel.tx" \
        -channelID $CHANNEL_ID \
        -asOrg "$2-msp"

    echo
    echo "Creating channel..."

    docker exec \
        -e "CORE_PEER_MSPCONFIGPATH=/etc/hyperledger/fabric/msp/users/Admin@$2.divvy.com/msp" \
        $CONTAINER peer channel create \
        -o orderer.divvy.com:7050 \
        -c "$CHANNEL_ID" \
        -f ./org-config/channel.tx

    if [ $? -ne 0 ]; then
        exit 1
    fi

    echo
    echo "Adding peer to channel..."

    docker exec \
        -e "CORE_PEER_MSPCONFIGPATH=/etc/hyperledger/fabric/msp/users/Admin@$2.divvy.com/msp" \
        $CONTAINER peer channel join \
        -b "$CHANNEL_ID.block"

    if [ $? -ne 0 ]; then
        exit 1
    fi

    # Check the peer successfully joined the channel.
    echo
    docker exec $CONTAINER peer channel list

    if [ $? -ne 0 ]; then
        exit 1
    fi

    echo
    echo "Adding anchor peer config to channel..."

    docker exec \
        -e "CORE_PEER_MSPCONFIGPATH=/etc/hyperledger/fabric/msp/users/Admin@$2.divvy.com/msp" \
        $CONTAINER peer channel update \
        -o orderer.divvy.com:7050 \
        -c "$CHANNEL_ID" \
        -f ./org-config/"$2-msp-anchor-$2-channel.tx"

    if [ $? -ne 0 ]; then
        exit 1
    fi
}

checkPrereqs

MODE=$1
shift

if [ "$MODE" != "create" ] && [ "$MODE" != "remove" ] && [ "$MODE" != "joinchannel" ]; then
    printHelp
    exit 1
fi

POSITIONAL=()
while [[ $# -gt 0 ]]
do
    opt="$1"
    case "$opt" in
        --help)
            printHelp
            exit 0
            ;;
        --org)
            ORG="$(generateSlug $2)"
            MSP_NAME="${ORG}-msp"
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
        --channel)
            CHANNEL=$2
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

if [ "$ORG" == "" ]; then
    echo "No organisation name specified."
    echo
    printHelp
    exit 1
fi

askProceed

CONFIG_DIR="$PWD/org-config/$ORG"
VOLUME_DIR="peer.$ORG.divvy.com"

if [ "$MODE" == "create" ]; then
    if [ "$PEER_PORT" == "" ]; then
        echo "No peer port specified."
        echo
        printHelp
        exit 1
    fi

    if [ "$CA_PORT" == "" ]; then
        echo "No CA port specified."
        echo
        printHelp
        exit 1
    fi

    if [ -d $CONFIG_DIR ]; then
        echo "There is already an organisation called ${ORG}."
        exit 1
    fi

    mkdir -p $CONFIG_DIR

    echo "Generating crypto config for ${ORG}..."
    generateCryptoConfig $ORG > "$CONFIG_DIR/crypto-config.yaml"
    echo

    echo "Generating certificates for trust domain:"
    generateCryptoMaterial "$CONFIG_DIR/crypto-config.yaml"
    echo

    echo "Generating network config..."
    generateNetworkConfig $ORG $MSP_NAME $PEER_PORT > "$CONFIG_DIR/configtx.yaml"
    echo

    echo "Generating Org definition..."
    generateOrgDefinition $CONFIG_DIR $MSP_NAME > "$CONFIG_DIR/${ORG}.json"
    echo

    echo "Generating connection profile..."
    generateConnectionProfile $ORG $MSP_NAME $PEER_PORT $CA_PORT > "$CONFIG_DIR/connection-profile.yaml"
    echo

    echo "Generating docker compose file..."
    generateDockerCompose $ORG $MSP_NAME $PEER_PORT $CA_PORT > "$CONFIG_DIR/docker-compose.yaml"
    echo

    echo "Starting Organisation containers..."
    echo
    docker-compose -f "$CONFIG_DIR/docker-compose.yaml" up -d 2>&1

    sleep 10

    echo
    docker ps -a --filter name=".$ORG.divvy.com"
    echo

    echo "Adding $ORG to the default consortium..."
    addOrgToConsortium $ORG $MSP_NAME
    echo

    createOrgChannel $CONFIG_DIR $ORG
    echo
elif [ "$MODE" == "remove" ]; then
    # TODO: Delete channel
    # TODO: Remove from consortium

    echo "Stopping $ORG containers..."
    docker-compose -f "$CONFIG_DIR/docker-compose.yaml" down --volumes
    echo

    echo "Removing files..."
    for dir in "$CA_DIR" "$CRYPTO_DIR" "$CONFIG_DIR" "$VOLUME_DIR"; do
        echo "Removing $dir"
        rm -rf $dir
    done
    echo
fi

echo "Done"
