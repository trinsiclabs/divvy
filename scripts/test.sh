#!/bin/bash

echo
echo " ____    _____      _      ____    _____ "
echo "/ ___|  |_   _|    / \    |  _ \  |_   _|"
echo "\___ \    | |     / _ \   | |_) |   | |  "
echo " ___) |   | |    / ___ \  |  _ <    | |  "
echo "|____/    |_|   /_/   \_\ |_| \_\   |_|  "
echo
echo "Divvy end-to-end test"
echo
CHANNEL_NAME="$1"
DELAY="$2"
TIMEOUT="$3"
VERBOSE="$4"
NO_CHAINCODE="$5"
: ${CHANNEL_NAME:="testchannel"}
: ${DELAY:="3"}
: ${TIMEOUT:="10"}
: ${VERBOSE:="false"}
: ${NO_CHAINCODE:="false"}
COUNTER=1
MAX_RETRY=10
CC_SRC_PATH="/opt/gopath/src/github.com/chaincode"

echo "Channel name : "$CHANNEL_NAME

# import utils
. scripts/utils.sh

createChannel() {
    setGlobals 1

    if [ -z "$CORE_PEER_TLS_ENABLED" -o "$CORE_PEER_TLS_ENABLED" = "false" ]; then
        set -x
        peer channel create -o orderer.divvy.com:7050 -c $CHANNEL_NAME -f ./channel-artifacts/channel.tx >&log.txt
        res=$?
        set +x
    else
        set -x
        peer channel create -o orderer.divvy.com:7050 -c $CHANNEL_NAME -f ./channel-artifacts/channel.tx --tls $CORE_PEER_TLS_ENABLED --cafile $ORDERER_CA >&log.txt
        res=$?
        set +x
    fi

    cat log.txt
    verifyResult $res "Channel creation failed"
    echo "===================== Channel '$CHANNEL_NAME' created ===================== "
    echo
}

joinChannel () {
    for org in 1 2; do
        joinChannelWithRetry $org
        echo "===================== peer.org${org} joined channel '$CHANNEL_NAME' ===================== "
        sleep $DELAY
        echo
    done
}

## Create channel
echo "Creating channel..."
createChannel

## Join all the peers to the channel
echo "Having all peers join the channel..."
joinChannel

## Set the anchor peers for each org in the channel
echo "Updating anchor peers for org1..."
updateAnchorPeers 1
echo "Updating anchor peers for org2..."
updateAnchorPeers 2

if [ "${NO_CHAINCODE}" != "true" ]; then
    ## Install chaincode on peer.org1 and peer.org2
    echo "Installing chaincode on peer.org1..."
    installChaincode 1
    echo "Install chaincode on peer.org2..."
    installChaincode 2

    # Instantiate chaincode on peer.org2
    echo "Instantiating chaincode on peer.org2..."
    instantiateChaincode 2

    # Query chaincode on peer.org1
    echo "Querying chaincode on peer.org1..."
    chaincodeQuery 1 100

    # Invoke chaincode on peer.org1 and peer.org2
    echo "Sending invoke transaction on peer.org1 peer.org2..."
    chaincodeInvoke 0 1 0 2
fi

echo
echo "========= All GOOD, execution completed =========== "
echo

echo
echo " _____   _   _   ____   "
echo "| ____| | \ | | |  _ \  "
echo "|  _|   |  \| | | | | | "
echo "| |___  | |\  | | |_| | "
echo "|_____| |_| \_| |____/  "
echo

exit 0
