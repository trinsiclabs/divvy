#!/bin/bash

# Obtain the OS and Architecture string that will be used to select the correct
# native binaries for your platform, e.g., darwin-amd64 or linux-amd64
OS_ARCH=$(echo "$(uname -s | tr '[:upper:]' '[:lower:]' | sed 's/mingw64_nt.*/windows/')-$(uname -m | sed 's/x86_64/amd64/g')" | awk '{print tolower($0)}')

# timeout duration - the duration the CLI should wait for a response from
# another container before giving up
CLI_TIMEOUT=10

# default for delay between commands
CLI_DELAY=3

# system channel name defaults to "sys-channel"
SYS_CHANNEL="sys-channel"

# channel name defaults to "divvy"
CHANNEL_NAME="divvy"

# use this as the default docker-compose yaml definition
COMPOSE_FILE=docker-compose.yaml

# couchdb composer file
COMPOSE_FILE_COUCH=docker-compose-couch.yaml

# org3 docker compose file
COMPOSE_FILE_ORG3=docker-compose-org3.yaml

# two additional etcd/raft orderers
COMPOSE_FILE_RAFT2=docker-compose-etcdraft2.yaml

# default image tag
IMAGETAG="1.4.3"

# default consensus type
CONSENSUS_TYPE="solo"

# Print the usage message
function printHelp() {
    echo "Usage: "
    echo "  divvy.sh <mode> [-c <channel name>] [-t <timeout>] [-d <delay>] [-f <docker-compose-file>] [-s <dbtype>] [-l <language>] [-o <consensus-type>] [-i <imagetag>] [-a] [-n] [-v]"
    echo "    <mode> - one of 'up', 'down', 'restart' or 'generate'"
    echo "      - 'up' - bring up the network with docker-compose up"
    echo "      - 'down' - clear the network with docker-compose down"
    echo "      - 'restart' - restart the network"
    echo "      - 'generate' - generate required certificates and genesis block"
    echo "    -c <channel name> - channel name to use (defaults to \"divvy\")"
    echo "    -t <timeout> - CLI timeout duration in seconds (defaults to 10)"
    echo "    -d <delay> - delay duration in seconds (defaults to 3)"
    echo "    -f <docker-compose-file> - specify which docker-compose file use (defaults to docker-compose.yaml)"
    echo "    -s <dbtype> - the database backend to use: goleveldb (default) or couchdb"
    echo "    -o <consensus-type> - the consensus-type of the ordering service: solo (default) or etcdraft"
    echo "    -i <imagetag> - the tag to be used to launch the network (defaults to \"latest\")"
    echo "    -n - do not deploy chaincode (abstore chaincode is deployed by default)"
    echo "    -v - verbose mode"
    echo "  divvy.sh -h (print this message)"
    echo
    echo "Typically, one would first generate the required certificates and "
    echo "genesis block, then bring up the network. e.g.:"
    echo
    echo "	divvy.sh generate -c mychannel"
    echo "	divvy.sh up -c mychannel -s couchdb"
    echo "        divvy.sh up -c mychannel -s couchdb -i 1.4.0"
    echo "	divvy.sh up -l golang"
    echo "	divvy.sh down -c mychannel"
    echo "        divvy.sh upgrade -c mychannel"
    echo
    echo "Taking all defaults:"
    echo "	divvy.sh generate"
    echo "	divvy.sh up"
    echo "	divvy.sh down"
}

# Ask user for confirmation to proceed
function askProceed() {
    read -p "Continue? [Y/n] " ans
    case "$ans" in
    y | Y | "")
        echo "proceeding ..."
        ;;
    n | N)
        echo "exiting..."
        exit 1
        ;;
    *)
        echo "invalid response"
        askProceed
        ;;
    esac
}

# Do some basic sanity checking to make sure that the appropriate versions of fabric
# binaries/images are available. In the future, additional checking for the presence
# of go or other items could be added.
function checkPrereqs() {
    # Note, we check configtxlator externally because it does not require a config file, and peer in the
    # docker image because of FAB-8551 that makes configtxlator return 'development version' in docker
    LOCAL_VERSION=$(configtxlator version | sed -ne 's/ Version: //p')
    DOCKER_IMAGE_VERSION=$(docker run --rm hyperledger/fabric-tools:$IMAGETAG peer version | sed -ne 's/ Version: //p' | head -1)

    echo "LOCAL_VERSION=$LOCAL_VERSION"
    echo "DOCKER_IMAGE_VERSION=$DOCKER_IMAGE_VERSION"

    if [ "$LOCAL_VERSION" != "$DOCKER_IMAGE_VERSION" ]; then
        echo "=================== WARNING ==================="
        echo "  Local fabric binaries and docker images are  "
        echo "  out of sync. This may cause problems.        "
        echo "==============================================="
    fi
}

function one_line_pem {
    echo "`awk 'NF {sub(/\\n/, ""); printf "%s\\\\\\\n",$0;}' $1`"
}

function generate_json_ccp {
    local PP=$(one_line_pem $4)
    local CP=$(one_line_pem $5)
    sed -e "s/\${ORG}/$1/" \
        -e "s/\${PEERPORT}/$2/" \
        -e "s/\${CAPORT}/$3/" \
        -e "s#\${PEERPEM}#$PP#" \
        -e "s#\${CAPEM}#$CP#" \
        ./templates/connection-profile-template.json
}

function generate_yaml_ccp {
    local PP=$(one_line_pem $4)
    local CP=$(one_line_pem $5)
    sed -e "s/\${ORG}/$1/" \
        -e "s/\${PEERPORT}/$2/" \
        -e "s/\${CAPORT}/$3/" \
        -e "s#\${PEERPEM}#$PP#" \
        -e "s#\${CAPEM}#$CP#" \
        ./templates/connection-profile-template.yaml | sed -e $'s/\\\\n/\\\n        /g'
}

function generate_ca_config {
    sed -e "s/\${ORG}/$1/g" ./templates/ca-config-template.yaml
}

# We will use the cryptogen tool to generate the cryptographic material (x509 certs)
# for our various network entities. The certificates are based on a standard PKI
# implementation where validation is achieved by reaching a common trust anchor.
#
# Cryptogen consumes a file - ``config/crypto.yaml`` - that contains the network
# topology and allows us to generate a library of certificates for both the
# Organizations and the components that belong to those Organizations. Each
# Organization is provisioned a unique root certificate (``ca-cert``), that binds
# specific components (peers and orderers) to that Org. Transactions and communications
# within Fabric are signed by an entity's private key (``keystore``), and then verified
# by means of a public key (``signcerts``). You will notice a "count" variable within
# this file. We use this to specify the number of peers per Organization; in our
# case it's two peers per Org. The rest of this template is extremely
# self-explanatory.
#
# After we run the tool, the certs will be parked in a folder titled ``crypto-config``.

# Generates Org certs using cryptogen tool
function generateCerts() {
    which cryptogen

    if [ "$?" -ne 0 ]; then
        echo "cryptogen tool not found. exiting"
        exit 1
    fi

    echo
    echo "##########################################################"
    echo "##### Generate certificates using cryptogen tool #########"
    echo "##########################################################"

    if [ -d "ca.divvy.com/ca" ]; then
        rm -Rf ca.divvy.com/ca
    fi

    if [ -d "crypto-config" ]; then
        rm -Rf crypto-config
    fi

    if [ -d "org-config" ]; then
        rm -Rf org-config
    fi

    set -x
    # TODO: Seperate Orgs into seperate files to they can be added dynamically.
    cryptogen generate --config=./config/crypto.yaml
    res=$?
    set +x

    if [ $res -ne 0 ]; then
        echo "Failed to generate certificates..."
        exit 1
    fi

    echo
    echo "Generate Connection Profiles for Org1 and Org2"

    # TODO: Remove hardcoding. Each Org should have its Connection Profile
    # generated dynamically.
    ORG=1
    PEERPORT=7051
    CAPORT=7054
    PEERPEM=crypto-config/peerOrganizations/org1.divvy.com/tlsca/tlsca.org1.divvy.com-cert.pem
    CAPEM=crypto-config/peerOrganizations/org1.divvy.com/ca/ca.org1.divvy.com-cert.pem

    mkdir -p ./org-config/org${ORG}
    mkdir -p ./ca.divvy.com/ca/org${ORG}

    echo "$(generate_json_ccp $ORG $PEERPORT $CAPORT $PEERPEM $CAPEM)" > ./org-config/org${ORG}/connection-profile.json
    echo "$(generate_yaml_ccp $ORG $PEERPORT $CAPORT $PEERPEM $CAPEM)" > ./org-config/org${ORG}/connection-profile.yaml
    echo "$(generate_ca_config $ORG)" > ./ca.divvy.com/ca/org${ORG}/ca-config.yaml

    ORG=2
    PEERPORT=8051
    CAPORT=7054
    PEERPEM=crypto-config/peerOrganizations/org2.divvy.com/tlsca/tlsca.org2.divvy.com-cert.pem
    CAPEM=crypto-config/peerOrganizations/org2.divvy.com/ca/ca.org2.divvy.com-cert.pem

    mkdir -p ./org-config/org${ORG}
    mkdir -p ./ca.divvy.com/ca/org${ORG}

    echo "$(generate_json_ccp $ORG $PEERPORT $CAPORT $PEERPEM $CAPEM)" > ./org-config/org${ORG}/connection-profile.json
    echo "$(generate_yaml_ccp $ORG $PEERPORT $CAPORT $PEERPEM $CAPEM)" > ./org-config/org${ORG}/connection-profile.yaml
    echo "$(generate_ca_config $ORG)" > ./ca.divvy.com/ca/org${ORG}/ca-config.yaml
}

# Replace constants with private key file names generated by the cryptogen tool.
function replacePrivateKey() {
    # sed on macOS does not support -i flag with a null extension. We will use
    # 't' for our back-up's extension and delete it at the end of the function
    ARCH=$(uname -s | grep Darwin)

    if [ "$ARCH" == "Darwin" ]; then
        OPTS="-it"
    else
        OPTS="-i"
    fi

    # The next steps will replace the template's contents with the
    # actual values of the private key file names for the two CAs.
    CURRENT_DIR=$PWD

    # TODO: Replace hardcoding.
    cd crypto-config/peerOrganizations/org1.divvy.com/ca/
    PRIV_KEY=$(ls *_sk)
    cd "$CURRENT_DIR"
    sed $OPTS "s/\${PRIV_KEY}/${PRIV_KEY}/g" ca.divvy.com/ca/org1/ca-config.yaml

    cd crypto-config/peerOrganizations/org2.divvy.com/ca/
    PRIV_KEY=$(ls *_sk)
    cd "$CURRENT_DIR"
    sed $OPTS "s/\${PRIV_KEY}/${PRIV_KEY}/g" ca.divvy.com/ca/org2/ca-config.yaml
}

# The `configtxgen tool is used to create four artifacts: orderer **bootstrap
# block**, fabric **channel configuration transaction**, and two **anchor
# peer transactions** - one for each Peer Org.
#
# The orderer block is the genesis block for the ordering service, and the
# channel transaction file is broadcast to the orderer at channel creation
# time. The anchor peer transactions, as the name might suggest, specify each
# Org's anchor peer on this channel.
#
# Configtxgen consumes a file - ``configtx.yaml`` - that contains the definitions
# for the sample network. There are three members - one Orderer Org (``OrdererOrg``)
# and two Peer Orgs (``Org1`` & ``Org2``) each managing and maintaining one peer node.
# This file also specifies a consortium - ``SampleConsortium`` - consisting of our
# two Peer Orgs. Pay specific attention to the "Profiles" section at the top of
# this file. You will notice that we have two unique headers. One for the orderer genesis
# block - ``TwoOrgsOrdererGenesis`` - and one for our channel - ``TwoOrgsChannel``.
# These headers are important, as we will pass them in as arguments when we create
# our artifacts. This file also contains two additional specifications that are worth
# noting. Firstly, we specify the anchor peers for each Peer Org
# (``peer.org1.divvy.com`` & ``peer.org2.divvy.com``). Secondly, we point to
# the location of the MSP directory for each member, in turn allowing us to store the
# root certificates for each Org in the orderer genesis block. This is a critical
# concept. Now any network entity communicating with the ordering service can have
# its digital signature verified.
#
# This function will generate the crypto material and our four configuration
# artifacts, and subsequently output these files into the ``channel-artifacts``
# folder.
#
# If you receive the following warning, it can be safely ignored:
#
# [bccsp] GetDefault -> WARN 001 Before using BCCSP, please call InitFactories(). Falling back to bootBCCSP.
#
# You can ignore the logs regarding intermediate certs, we are not using them in
# this crypto implementation.

# Generate orderer genesis block, channel configuration transaction and
# anchor peer update transactions
function generateChannelArtifacts() {
    which configtxgen

    if [ "$?" -ne 0 ]; then
        echo "configtxgen tool not found. exiting"
        exit 1
    fi

    echo "##########################################################"
    echo "#########  Generating Orderer Genesis block ##############"
    echo "##########################################################"

    if [ -d "channel-artifacts" ]; then
        rm -Rf channel-artifacts
    fi

    mkdir channel-artifacts

    # Note: For some unknown reason (at least for now) the block file can't be
    # named orderer.genesis.block or the orderer will fail to launch!
    echo "CONSENSUS_TYPE="$CONSENSUS_TYPE

    set -x

    if [ "$CONSENSUS_TYPE" == "solo" ]; then
        configtxgen -profile DivvyGenesis -channelID $SYS_CHANNEL -outputBlock ./channel-artifacts/genesis.block
    elif [ "$CONSENSUS_TYPE" == "etcdraft" ]; then
        configtxgen -profile SampleDevModeEtcdRaft -channelID $SYS_CHANNEL -outputBlock ./channel-artifacts/genesis.block
    else
        set +x
        echo "unrecognized CONSESUS_TYPE='$CONSENSUS_TYPE'. exiting"
        exit 1
    fi

    res=$?
    set +x

    if [ $res -ne 0 ]; then
        echo "Failed to generate orderer genesis block..."
        exit 1
    fi

    echo
    echo "#################################################################"
    echo "### Generating channel configuration transaction 'channel.tx' ###"
    echo "#################################################################"

    set -x
    configtxgen -profile TwoOrgsChannel -outputCreateChannelTx ./channel-artifacts/channel.tx -channelID $CHANNEL_NAME
    res=$?
    set +x

    if [ $res -ne 0 ]; then
        echo "Failed to generate channel configuration transaction..."
        exit 1
    fi

    echo
    echo "#################################################################"
    echo "#######    Generating anchor peer update for Org1MSP   ##########"
    echo "#################################################################"

    set -x
    configtxgen -profile TwoOrgsChannel -outputAnchorPeersUpdate ./channel-artifacts/Org1MSPanchors.tx -channelID $CHANNEL_NAME -asOrg Org1MSP
    res=$?
    set +x

    if [ $res -ne 0 ]; then
        echo "Failed to generate anchor peer update for Org1MSP..."
        exit 1
    fi

    echo
    echo "#################################################################"
    echo "#######    Generating anchor peer update for Org2MSP   ##########"
    echo "#################################################################"

    set -x
    configtxgen -profile TwoOrgsChannel -outputAnchorPeersUpdate \
        ./channel-artifacts/Org2MSPanchors.tx -channelID $CHANNEL_NAME -asOrg Org2MSP
    res=$?
    set +x

    if [ $res -ne 0 ]; then
        echo "Failed to generate anchor peer update for Org2MSP..."
        exit 1
    fi

    echo
}

# Generate the needed certificates, the genesis block and start the network.
function networkUp() {
    checkPrereqs

    # generate artifacts if they don't exist
    if [ ! -d "crypto-config" ]; then
        generateCerts
        replacePrivateKey
        generateChannelArtifacts
    fi

    COMPOSE_FILES="-f ${COMPOSE_FILE}"

    if [ "${CONSENSUS_TYPE}" == "etcdraft" ]; then
        COMPOSE_FILES="${COMPOSE_FILES} -f ${COMPOSE_FILE_RAFT2}"
    fi

    if [ "${IF_COUCHDB}" == "couchdb" ]; then
        COMPOSE_FILES="${COMPOSE_FILES} -f ${COMPOSE_FILE_COUCH}"
    fi

    IMAGE_TAG=$IMAGETAG docker-compose ${COMPOSE_FILES} up -d 2>&1
    docker ps -a

    if [ $? -ne 0 ]; then
        echo "ERROR !!!! Unable to start network"
        exit 1
    fi

    if [ "$CONSENSUS_TYPE" == "etcdraft" ]; then
        sleep 1
        echo "Sleeping 15s to allow $CONSENSUS_TYPE cluster to complete booting"
        sleep 14
    fi

    # now run the end to end script
    docker exec cli scripts/test.sh $CHANNEL_NAME $CLI_DELAY $CLI_TIMEOUT $VERBOSE $NO_CHAINCODE

    if [ $? -ne 0 ]; then
        echo "ERROR !!!! Test failed"
        exit 1
    fi
}

# Obtain CONTAINER_IDS and remove them
# TODO Might want to make this optional - could clear other containers
function clearContainers() {
    CONTAINER_IDS=$(docker ps -a | awk '($2 ~ /hyperledger.*/) {print $1}')

    if [ -z "$CONTAINER_IDS" -o "$CONTAINER_IDS" == " " ]; then
        echo "---- No containers available for deletion ----"
    else
        docker rm -f $CONTAINER_IDS
    fi
}

# Delete any images that were generated as a part of this setup
# specifically the following images are often left behind:
# TODO list generated image naming patterns
function removeUnwantedImages() {
    DOCKER_IMAGE_IDS=$(docker images | awk '($1 ~ /dev-peer.*/) {print $3}')

    if [ -z "$DOCKER_IMAGE_IDS" -o "$DOCKER_IMAGE_IDS" == " " ]; then
        echo "---- No images available for deletion ----"
    else
        docker rmi -f $DOCKER_IMAGE_IDS
    fi
}

# Tear down running network
function networkDown() {
    # stop org3 containers also in addition to org1 and org2, in case we were running sample to add org3
    docker-compose -f $COMPOSE_FILE -f $COMPOSE_FILE_COUCH -f $COMPOSE_FILE_RAFT2 -f $COMPOSE_FILE_ORG3 down --volumes --remove-orphans

    # Don't remove the generated artifacts -- note, the ledgers are always removed
    if [ "$MODE" != "restart" ]; then
        # Bring down the network, deleting the volumes
        # Delete any ledger backups
        docker run -v $PWD:/tmp/divvy --rm hyperledger/fabric-tools:$IMAGETAG rm -Rf /tmp/divvy/ledgers-backup

        # Cleanup the chaincode containers
        clearContainers

        # Cleanup images
        removeUnwantedImages

        # remove orderer block and other channel configuration transactions and certs
        rm -rf channel-artifacts/*.block channel-artifacts/*.tx crypto-config ./org3-artifacts/crypto-config/ channel-artifacts/org3.json
    fi
}

MODE=$1
shift

# Determine whether starting, stopping, restarting, generating or upgrading
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

while getopts "h?c:t:d:f:s:l:i:o:anv" opt; do
    case "$opt" in
    h | \?)
        printHelp
        exit 0
        ;;
    c)
        CHANNEL_NAME=$OPTARG
        ;;
    t)
        CLI_TIMEOUT=$OPTARG
        ;;
    d)
        CLI_DELAY=$OPTARG
        ;;
    f)
        COMPOSE_FILE=$OPTARG
        ;;
    s)
        IF_COUCHDB=$OPTARG
        ;;
    i)
        IMAGETAG=$(go env GOARCH)"-"$OPTARG
        ;;
    o)
        CONSENSUS_TYPE=$OPTARG
        ;;
    n)
        NO_CHAINCODE=true
        ;;
    v)
        VERBOSE=true
        ;;
    esac
done

# Announce what was requested
if [ "${IF_COUCHDB}" == "couchdb" ]; then
    echo
    echo "${EXPMODE} for channel '${CHANNEL_NAME}' with CLI timeout of '${CLI_TIMEOUT}' seconds and CLI delay of '${CLI_DELAY}' seconds and using database '${IF_COUCHDB}'"
else
    echo "${EXPMODE} for channel '${CHANNEL_NAME}' with CLI timeout of '${CLI_TIMEOUT}' seconds and CLI delay of '${CLI_DELAY}' seconds"
fi

# ask for confirmation to proceed
askProceed

# create the network using docker compose
if [ "${MODE}" == "up" ]; then
    networkUp
elif [ "${MODE}" == "down" ]; then ## Clear the network
    networkDown
elif [ "${MODE}" == "generate" ]; then ## Generate Artifacts
    generateCerts
    replacePrivateKey
    generateChannelArtifacts
elif [ "${MODE}" == "restart" ]; then ## Restart the network
    networkDown
    networkUp
else
    printHelp
    exit 1
fi
