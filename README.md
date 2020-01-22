# divvy

## Getting started

1. Install [Go](https://golang.org/)
2. Install [Node.js](nodejs.org)
3. Install [Docker](https://www.docker.com/)
4. From the `chaincode` directory, install the Node.js dependencies `$ npm install`
5. From the project root directory, install the Docker images and binaries `$ ./bootstrap.sh`
6. Reset the config file `git checkout config/configtx.yaml` (it gets clobbered by bootstrapping).
7. Add the `./bin` directory to your PATH `export PATH=$PWD/bin:$PATH`
8. Set FABRIC_CFG_PATH `export FABRIC_CFG_PATH=$PWD/config` (used by binaries in `./bin`)
9. Generate required crypto material, config, and genesis block `$ ./network generate`
10. Bring the network up (and run the tests) `$ ./network up`

## Creating an Organisation

`$ ./createorg.sh --name <org name>`

## Removing an Organisation

`$ ./removeorg.sh --name <org name>`
