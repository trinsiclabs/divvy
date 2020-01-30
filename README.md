# Divvy

Micro-equity platform built on
[Hyperledger Fabric](https://www.hyperledger.org/projects/fabric)

## Getting started

There are a few things to cover, so allow yourself an hour to get
up and running.

### Install the prerequisites

* [Docker](https://www.docker.com/)
* [Node.js](nodejs.org) v10.x.x

Here's a quick introduction to the various platform components.

#### Network

For more info, see the [network docs](./network/README.md).

#### Chaincode

For more info, see the [chaincode docs](./chaincode/README.md).

#### API

For more info, see the [API docs](./api/README.md).

### Bootstrap the network

From the `network` directory:

```
$ ./bootstrap.sh
```

This installs the required docker images and Fabric binaries.

### Prepare the chaincode

From the `chaincode` directory:

```
$ npm install
```

This installs the JavaScript dependencies required to run the chaincode.

### Bring the network up

From the `network` directory:

```
$ ./network.sh up
```

This brings up a skeleton network consisting of an order and CA.

### Populate the network

Add a couple of organisations to the network:

```
$ ./organisation.sh create --org org1 --pport 8051 --ccport 8052 --caport 8053
$ ./organisation.sh create --org org2 --pport 9051 --ccport 9052 --caport 9053
```

Join org1 to the org2 channel:

```
$ ./organisation.sh joinchannel --org org1 --channelowner org2
```

### Make a trade

Log into the org1 cli container:

```
docker exec -it cli.org1.divvy.com bash
```

See the current height and hash of the org1 blockchain:

```
peer channel getinfo -c org1-channel
```

Transfer ownership of a share from org1 to org2:

```
peer chaincode invoke -C org1-channel -n share -c '{"Args":["com.divvy.share:changeShareOwner","org1","1","org1","org2"]}' --tls --cafile /opt/gopath/src/github.com/hyperledger/fabric/orderer/msp/tlscacerts/tlsca.divvy.com-cert.pem
```

See the new height and hash of the org1 blockchain:

```
peer channel getinfo -c org1-channel
```

Verify the share has changed ownership:

```
peer chaincode query -C org1-channel -n share -c '{"Args":["com.divvy.share:queryShare","org1","1"]}'
```
