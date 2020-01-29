# divvy

Micro-equity platform built on
[Hyperledger Fabric](https://www.hyperledger.org/projects/fabric)

## Getting started

1. Install [Docker](https://www.docker.com/)
2. Install [Node.js](nodejs.org) v10.x.x
3. Install the Docker images and binaries: `$ ./bootstrap.sh`
4. Install the chaincode dependencies (from `./chaincode`): `$ npm install`
5. Bring the network up: `$ ./network up`

You should now have a running network consisting of a CA, Orderer Org with a
solo peer, and a CLI container.

## Network management

There are two scripts used to manage the Fabric network.

### network.sh

Used for managing the network, bringing it up and down.
For more info try `$ ./network.sh --help`

### organisation.sh

Used for organisation operation such as creating orgs and joining channels.
For more info try `$ ./organisation.sh --help`
