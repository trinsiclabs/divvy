# divvy

## Getting started

1. Install [Go](https://golang.org/)
2. Install [Node.js](nodejs.org) v10.x.x
3. Install [Docker](https://www.docker.com/)
4. From the project root directory, install the Docker images and binaries `$ ./bootstrap.sh`
5. Bring the network up for the first time `$ ./network up`

You should now have a running network consisting of a CA, an Orderer Org with a
solo peer, and a CLI container. The network is managed using
the `network.sh` script.

You can create and manage Organisations using the `organisation.sh` script.
