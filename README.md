# divvy

## Getting started

1. Install [Go](https://golang.org/)
2. Install [Node.js](nodejs.org)
3. Install [Docker](https://www.docker.com/)
4. From the `chaincode` directory, install the Node.js dependencies `$ npm install`
5. From the project root directory, install the Docker images and binaries `$ ./bootstrap.sh`
6. Add the `./bin` directory to your PATH `export PATH=$PWD/bin:$PATH`
7. Set FABRIC_CFG_PATH `export FABRIC_CFG_PATH=config` (used by binaries in `./bin`)
8. Generate required crypto material, config, and genesis block `$ ./divvy generate`
9. Bring the network up (and run the tests) `$ ./divvy up`
