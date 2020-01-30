# Divvy

Micro-equity platform built on
[Hyperledger Fabric](https://www.hyperledger.org/projects/fabric)

## Getting started

There are a few things to cover, so allow yourself an hour to get
up and running.

### Install the prerequisites

You need these things installed to run the platform.

* [Docker](https://www.docker.com/)
* [Node.js](nodejs.org) v10.x.x

While those are downloading, here's a quick introduction to the
various platform components.

#### Network

Hyperledger Fabric network with configuration and scripts living in
the `network` directory. This is the core platform component.

#### Chaincode

Chaincode is used by network peers to query and update ledger state.
It lives in the `chaincode` directory.

#### API (not working yet)

The API component connects client apps to the network and lives in
the `api` directory.

### Bootstrap the network

Once you have installed the prerequisites you're ready to
bootstrap the network. This only needs to be done once.

From the `network` directory:

```
$ ./bootstrap.sh
```

You should now have the required docker images and Fabric binaries installed.

### Prepare the chaincode

From the `chaincode` directory:

```
$ npm install
```

This installs the JavaScript dependencies required to run chaincode.

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
