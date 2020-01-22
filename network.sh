#!/bin/bash

export PATH=$PWD/bin:$PATH

# timeout duration - the duration the CLI should wait for a response from
# another container before giving up
# CLI_TIMEOUT=10

# default for delay between commands
# CLI_DELAY=3

. utils.sh

# Print the usage message
function printHelp() {
    echo "Usage: "
    echo "  network.sh <mode>"
    echo "    <mode> - one of 'up', 'down', 'restart' or 'generate'"
    echo "      - 'up' - bring up the network with docker-compose up"
    echo "      - 'down' - clear the network with docker-compose down"
    echo "      - 'restart' - restart the network"
    echo "      - 'generate' - generate required certificates and genesis block"
    echo "  network.sh -h (print this message)"
}

function checkPrereqs() {
    # Note, we check configtxlator externally because it does not require a config file, and peer in the
    # docker image because of FAB-8551 that makes configtxlator return 'development version' in docker
    LOCAL_VERSION=$(configtxlator version | sed -ne 's/ Version: //p')
    DOCKER_IMAGE_VERSION=$(docker run --rm hyperledger/fabric-tools:1.4.4 peer version | sed -ne 's/ Version: //p' | head -1)

    echo "LOCAL_VERSION=$LOCAL_VERSION"
    echo "DOCKER_IMAGE_VERSION=$DOCKER_IMAGE_VERSION"

    if [ "$LOCAL_VERSION" != "$DOCKER_IMAGE_VERSION" ]; then
        echo "=================== WARNING ==================="
        echo "  Local fabric binaries and docker images are  "
        echo "  out of sync. This may cause problems.        "
        echo "==============================================="
    fi

    for tool in cryptogen configtxgen; do
        which $tool > /dev/null 2>&1

        if [ "$?" -ne 0 ]; then
            echo "${tool} not found. Have you run the bootstrap script?"
            exit 1
        fi
    done
}

function generateGenesisBlock() {
    if [ -d "channel-artifacts" ]; then
        rm -Rf channel-artifacts
    fi

    mkdir channel-artifacts

    configtxgen -profile Genesis -channelID sys-channel -outputBlock ./channel-artifacts/genesis.block

    if [ $? -ne 0 ]; then
        echo "Failed to generate orderer genesis block..."
        exit 1
    fi
}

function networkUp() {
    checkPrereqs

    if [ ! -d "crypto-config" ]; then
        echo "Generating certificates for orderer..."
        generateCryptoMaterial ./crypto-config.yaml
        echo

        echo "Generating genesis block..."
        generateGenesisBlock
        echo
    fi

    # TODO: Include all Org docker-compose.yaml files

    docker-compose -f docker-compose.yaml up -d 2>&1
    docker ps -a

    if [ $? -ne 0 ]; then
        echo "ERROR !!!! Unable to start network"
        exit 1
    fi

    # docker exec cli scripts/test.sh $CLI_DELAY $CLI_TIMEOUT $VERBOSE $NO_CHAINCODE
    # if [ $? -ne 0 ]; then
    #     echo "ERROR !!!! Test failed"
    #     exit 1
    # fi
}

function clearContainers() {
    CONTAINER_IDS=$(docker ps -a | awk '($2 ~ /dev-peer.*/) {print $1}')

    if [ -z "$CONTAINER_IDS" -o "$CONTAINER_IDS" == " " ]; then
        echo "---- No containers available for deletion ----"
    else
        docker rm -f $CONTAINER_IDS
    fi
}

function removeUnwantedImages() {
    DOCKER_IMAGE_IDS=$(docker images | awk '($1 ~ /dev-peer.*/) {print $3}')

    if [ -z "$DOCKER_IMAGE_IDS" -o "$DOCKER_IMAGE_IDS" == " " ]; then
        echo "---- No images available for deletion ----"
    else
        docker rmi -f $DOCKER_IMAGE_IDS
    fi
}

function networkDown() {
    #TODO: Include Organisation docker-compose.yaml files
    docker-compose -f docker-compose.yaml down --volumes --remove-orphans

    # Don't remove the generated artifacts -- note, the ledgers are always removed
    if [ "$MODE" != "restart" ]; then
        # Bring down the network, deleting the volumes
        # Delete any ledger backups
        docker run -v $PWD:/tmp/divvy --rm hyperledger/fabric-tools:1.4.4 rm -Rf /tmp/divvy/ledgers-backup

        clearContainers

        removeUnwantedImages

        # remove orderer block and other channel configuration transactions and certs
        rm -rf channel-artifacts/*.block channel-artifacts/*.tx crypto-config
    fi
}

MODE=$1
shift

if [ "$MODE" == "up" ]; then
    EXPMODE="Starting"
elif [ "$MODE" == "down" ]; then
    EXPMODE="Stopping"
elif [ "$MODE" == "restart" ]; then
    EXPMODE="Restarting"
elif [ "$MODE" == "generate" ]; then
    EXPMODE="Generating certs and genesis block"
else
    printHelp
    exit 1
fi

while getopts "h" opt; do
    case "$opt" in
        h)
            printHelp
            exit 0
            ;;
    esac
done

askProceed

if [ "${MODE}" == "up" ]; then
    networkUp
elif [ "${MODE}" == "down" ]; then ## Clear the network
    networkDown
elif [ "${MODE}" == "generate" ]; then ## Generate Artifacts
    echo "Generating certificates for orderer..."
    generateCryptoMaterial ./crypto-config.yaml
    echo

    echo "Generating genesis block..."
    generateGenesisBlock
    echo

    echo "Done"
elif [ "${MODE}" == "restart" ]; then ## Restart the network
    networkDown
    networkUp
else
    printHelp
    exit 1
fi
