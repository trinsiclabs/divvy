#!/bin/bash

ORDERER_CLI="cli.divvy.com"
ORDERER_PEER="orderer.divvy.com:7050"

ORG=""
PEER_PORT=""
CA_PORT=""
CHANNEL=""

MSP_NAME=""
CONFIG_DIR=""
VOLUME_DIR=""
CRYPTO_DIR=""
CLI_OUTPUT_DIR=""
ORG_CLI=""
ORG_PEER=""

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

function cliMkdirp() {
    echo
    echo "Creating directory $1 on $ORDERER_CLI..."
    echo

    docker exec $ORDERER_CLI mkdir -p $1

    if [ $? -ne 0 ]; then
        exit 1
    fi
}

function cliRmrf() {
    echo
    echo "Removing directory $1 on $ORDERER_CLI..."
    echo

    docker exec $ORDERER_CLI rm -rf $1

    if [ $? -ne 0 ]; then
        exit 1
    fi
}

function cliFetchLatestChannelConfigBlock() {
    echo
    echo "Fetching latest config block for channel $1..."
    echo

    docker exec $ORDERER_CLI peer channel fetch config $2 -o $ORDERER_PEER -c $1

    if [ $? -ne 0 ]; then
        exit 1
    fi
}

function cliDecodeConfigBlock() {
    echo
    echo "Decoding config block..."
    echo

    local type="${3:-common.Block}"
    local treePath="${4:-.data.data[0].payload.data.config}"

    docker exec -i $ORDERER_CLI bash <<EOF
        configtxlator proto_decode --input "$1" --type "$type" | jq "$treePath" > "$2"
EOF

    if [ $? -ne 0 ]; then
        exit 1
    fi
}

function cliEncodeConfigJson() {
    echo
    echo "Encoding config block..."
    echo

    local type="${3:-common.Config}"

    docker exec $ORDERER_CLI configtxlator proto_encode \
        --input $1 \
        --output $2 \
        --type $type

    if [ $? -ne 0 ]; then
        exit 1
    fi
}

function cliGenerateUpdateBlock() {
    echo
    echo "Generating config update block for channel $1..."
    echo

    docker exec $ORDERER_CLI configtxlator compute_update \
        --channel_id $1 \
        --original $2 \
        --updated $3 \
        --output $4

    if [ $? -ne 0 ]; then
        exit 1
    fi
}

function cliAddConfigUpdateHeader() {
    echo
    echo "Adding header to config update for channel $1..."
    echo

    docker exec -i \
        -e channel=$1 \
        -e updatesFile=$2 \
        -e outFile=$3 \
        $ORDERER_CLI bash -c 'updates=$(< $updatesFile); echo \''{\""payload\"":{\""header\"":{\""channel_header\"":{\""channel_id\"":\""$channel\"", \""type\"":2}},\""data\"":{\""config_update\"":$updates}}}\'' | jq . > $outFile'

    if [ $? -ne 0 ]; then
        exit 1
    fi
}

function cliSubmitChannelUpdate() {
    echo
    echo "Submitting config update for channel $2..."
    echo

    docker exec $ORDERER_CLI peer channel update -f $1 -c $2 -o $ORDERER_PEER

    if [ $? -ne 0 ]; then
        exit 1
    fi
}

function cliFetchChannelGenesisBlock() {
    echo
    echo "Fetching genesis block for channel $2..."
    echo

    docker exec $1 peer channel fetch 0 $3 -o $ORDERER_PEER -c $2

    if [ $? -ne 0 ]; then
        exit 1
    fi
}

function cliJoinPeerToChannel() {
    echo
    echo "Joining $ORG_PEER to channel $2..."
    echo

    docker exec $1 peer channel join -b $3

    if [ $? -ne 0 ]; then
        exit 1
    fi
}

function addOrgToConsortium() {
    local ORG_DEF="./org-config/$1/$1.json"
    local CONF_BLOCK="$CLI_OUTPUT_DIR/config-$1.pb"
    local CONF_MOD_BLOCK="$CLI_OUTPUT_DIR/config-modified-$1.pb"
    local CONF_DELTA_BLOCK="$CLI_OUTPUT_DIR/config-delta-$1.pb"
    local CONF_JSON="$CLI_OUTPUT_DIR/config-$1.json"
    local CONF_MOD_JSON="$CLI_OUTPUT_DIR/config-modified-$1.json"
    local CONF_DELTA_JSON="$CLI_OUTPUT_DIR/config-delta-$1.json"
    local PAYLOAD_BLOCK="$CLI_OUTPUT_DIR/payload-$1.pb"
    local PAYLOAD_JSON="$CLI_OUTPUT_DIR/payload-$1.json"

    cliMkdirp $CLI_OUTPUT_DIR

    cliFetchLatestChannelConfigBlock $CHANNEL $CONF_BLOCK

    cliDecodeConfigBlock $CONF_BLOCK $CONF_JSON

    # Add the Org definition to config.
    docker exec -i \
        -e MSP_NAME=$2 \
        -e CONF_JSON=$CONF_JSON \
        -e ORG_DEF=$ORG_DEF \
        -e CONF_MOD_JSON=$CONF_MOD_JSON \
        $ORDERER_CLI bash <<EOF
        jq -s --arg MSP_NAME "$MSP_NAME" '.[0] * {"channel_group":{"groups":{"Consortiums":{"groups": {"Default": {"groups": {"$MSP_NAME":.[1]}, "mod_policy": "/Channel/Orderer/Admins", "policies": {}, "values": {"ChannelCreationPolicy": {"mod_policy": "/Channel/Orderer/Admins","value": {"type": 3,"value": {"rule": "ANY","sub_policy": "Admins"}},"version": "0"}},"version": "0"}}}}}}' $CONF_JSON $ORG_DEF > $CONF_MOD_JSON
EOF

    if [ $? -ne 0 ]; then
        exit 1
    fi

    # Convert the origional (extracted) config to a block, so we can diff it against the updates.
    cliEncodeConfigJson $CONF_JSON $CONF_BLOCK

    # Convert the updated config to a block, so we can diff it against the origional.
    cliEncodeConfigJson $CONF_MOD_JSON $CONF_MOD_BLOCK

    # Diff the changes to create an "update" block.
    cliGenerateUpdateBlock $CHANNEL $CONF_BLOCK $CONF_MOD_BLOCK $CONF_DELTA_BLOCK

    # Convert the update block to JSON so we can add a header.
    cliDecodeConfigBlock $CONF_DELTA_BLOCK $CONF_DELTA_JSON common.ConfigUpdate '.'

    # Add the header.
    cliAddConfigUpdateHeader $CHANNEL $CONF_DELTA_JSON $PAYLOAD_JSON

    # Convert the payload to a block.
    cliEncodeConfigJson $PAYLOAD_JSON $PAYLOAD_BLOCK common.Envelope

    # Make the update.
    cliSubmitChannelUpdate $PAYLOAD_BLOCK $CHANNEL

    # Clean up.
    cliRmrf $CLI_OUTPUT_DIR
}

function createOrgChannel() {
    local orgChannelId="$2-channel"

    echo "Generating config transactions..."

    # Generate the channel configuration transation.
    configtxgen \
        -configPath $1 \
        -profile $orgChannelId \
        -outputCreateChannelTx "$1/channel.tx" \
        -channelID $orgChannelId

    # Generate the anchor peer transaction.
    configtxgen \
        -configPath $1 \
        -profile $orgChannelId \
        -outputAnchorPeersUpdate "$1/$2-msp-anchor-$2-channel.tx" \
        -channelID $orgChannelId \
        -asOrg "$2-msp"

    echo
    echo "Creating channel..."

    docker exec \
        -e "CORE_PEER_MSPCONFIGPATH=/etc/hyperledger/fabric/msp/users/Admin@$2.divvy.com/msp" \
        $ORG_PEER peer channel create \
        -o $ORDERER_PEER \
        -c "$orgChannelId" \
        -f ./org-config/channel.tx

    if [ $? -ne 0 ]; then
        exit 1
    fi

    echo
    echo "Adding peer to channel..."

    docker exec \
        -e "CORE_PEER_MSPCONFIGPATH=/etc/hyperledger/fabric/msp/users/Admin@$2.divvy.com/msp" \
        $ORG_PEER peer channel join \
        -b "$orgChannelId.block"

    if [ $? -ne 0 ]; then
        exit 1
    fi

    # Check the peer successfully joined the channel.
    echo
    docker exec $ORG_PEER peer channel list

    if [ $? -ne 0 ]; then
        exit 1
    fi

    echo
    echo "Adding anchor peer config to channel..."

    docker exec \
        -e "CORE_PEER_MSPCONFIGPATH=/etc/hyperledger/fabric/msp/users/Admin@$2.divvy.com/msp" \
        $ORG_PEER peer channel update \
        -o $ORDERER_PEER \
        -c "$orgChannelId" \
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
VOLUME_DIR="$PWD/peer.$ORG.divvy.com"
CRYPTO_DIR="$PWD/crypto-config/peerOrganizations/$ORG.divvy.com"
CLI_OUTPUT_DIR="./org-artifacts/$ORG"
ORG_CLI="cli.$ORG.divvy.com"
ORG_PEER="peer.$ORG.divvy.com"

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

    CHANNEL='sys-channel'

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
    for dir in "$CRYPTO_DIR" "$CONFIG_DIR" "$VOLUME_DIR"; do
        echo "Removing $dir"
        rm -rf $dir
    done
    echo
elif [ "$MODE" == "joinchannel" ]; then
    if [ "$CHANNEL" == "" ]; then
        echo "No channel specified."
        echo
        printHelp
        exit 1
    fi

    if [ ! -d "$CONFIG_DIR" ]; then
        echo "Invalid org name. Did you spell the org name correctly?"
        exit 1
    fi

    configBlock="$CLI_OUTPUT_DIR/config-$CHANNEL.pb"
    configBlockUpdated="$CLI_OUTPUT_DIR/config-$CHANNEL-updated.pb"
    configJson="$CLI_OUTPUT_DIR/config-$CHANNEL.json"
    configJsonUpdated="$CLI_OUTPUT_DIR/config-$CHANNEL-updated.json"
    payloadBlock="$CLI_OUTPUT_DIR/config-$CHANNEL-payload.pb"
    payloadJson="$CLI_OUTPUT_DIR/config-$CHANNEL-payload.json"
    orgDefinition="./org-config/$ORG/$ORG.json"
    channelGenesisBlock="$CHANNEL.block"

    cliMkdirp $CLI_OUTPUT_DIR

    cliFetchLatestChannelConfigBlock $CHANNEL $configBlock

    cliDecodeConfigBlock $configBlock $configJson

    # Add Org to config.
    docker exec -i \
        -e mspName=$MSP_NAME \
        -e configJson=$configJson \
        -e orgDefinition=$orgDefinition \
        -e configJsonUpdated=$configJsonUpdated \
        $ORDERER_CLI bash <<EOF
        jq -s '.[0] * {"channel_group":{"groups":{"Application":{"groups": {"$mspName":.[1]}}}}}' $configJson $orgDefinition > $configJsonUpdated
EOF

    if [ $? -ne 0 ]; then
        exit 1
    fi
set -x
    # Convert the origional (extracted) config to a block, so we can diff it against the updates.
    cliEncodeConfigJson $configJson $configBlock

    # Convert the updated config to a block, so we can diff it against the origional.
    cliEncodeConfigJson $configJsonUpdated $configBlockUpdated

    # Diff the changes to create an "update" block.
    cliGenerateUpdateBlock $CHANNEL $configBlock $configBlockUpdated $payloadBlock

    # Convert the update block to JSON so we can add a header.
    cliDecodeConfigBlock $payloadBlock $payloadJson common.ConfigUpdate '.'

    # Add the header.
    cliAddConfigUpdateHeader $CHANNEL $payloadJson $payloadJson

    # Convert the payload to a block.
    cliEncodeConfigJson $payloadJson $payloadBlock common.Envelope

    # Submit the block.
    cliSubmitChannelUpdate $payloadBlock $CHANNEL
set +x
    # Clean up.
    cliRmrf $CLI_OUTPUT_DIR

    # Fetch the genesis block to start syncing the new org peer's ledger
    cliFetchChannelGenesisBlock $ORG_CLI $CHANNEL $channelGenesisBlock

    # Join peer to channel
    cliJoinPeerToChannel $ORG_CLI $CHANNEL $channelGenesisBlock
fi

echo "Done"
