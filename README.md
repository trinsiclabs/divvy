# Divvy

Micro-equity platform built on
[Hyperledger Fabric](https://www.hyperledger.org/projects/fabric)

## Getting started

There are a few things to cover, so allow yourself an hour to get
up and running.

### Install the prerequisites

You'll need these things installed to run the platform.

* [Vagrant](https://www.vagrantup.com/)
* [VirtualBox](https://www.virtualbox.org/)

You'll also need about 10gb of free space available.

### Platform components

While things are downloading, here's a quick introduction to the
various platform components.

#### Host

The host is responsible for running all services which make up the platform.
It is a Vagrant virtual machine running Ubuntu 18.04 LTS with
[Docker](https://www.docker.com/) installed. The following components run on
the host as Docker containers.

#### Network

Hyperledger Fabric network, the core platform component.

It has three core containers:

* ca.divvy.com
* orderer.divvy.com
* cli.divvy.com

The network is initially empty, it has no organisations. Each organisation
added to the network includes three more containers:

* ca.ORG_NAME.divvy.com
* peer.ORG_NAME.divvy.com
* cli.ORG_NAME.divvy.com

See the [network docs](https://github.com/flashbackzoo/divvy-network) for more info.

#### Chaincode

Chaincode is used by network peers to query and update ledger state.

See the [chaincode docs](https://github.com/flashbackzoo/divvy-chaincode) for more info.

#### Client App

Primary user interface (UI) for interacting with the network.
Users can signup (create an organisation), join channels,
and trade shares using the app.

See the [application docs](https://github.com/flashbackzoo/divvy-application) for more info.

#### API

The API component connects the client app to the network.

See the [API docs](https://github.com/flashbackzoo/divvy-api) for ore info.

### Bootstrap the host

Once you have installed the prerequisites you're ready to
bootstrap the host virtual machine.

```
$ vagrant up
```

This will download the `ubuntu/bionic64` image (if you don't have it already),
provision the box, pull the required Docker images, Fabric binaries,
and a few other things. The provisioning script is in `Vagrantfile` if you want
to see exactly what happens.

Once provisioning is complete (it will take a few minutes) you're ready to
start using the network.

Login to the host:

```
$ vagrant ssh
```

**Note all CLI interactions with the network must be performed from the host**

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

Join org2 to the org1 channel:

```
$ ./organisation.sh joinchannel --org org2 --channelowner org1
```

### Make a trade

Log into the org1 cli container:

```
sudo docker exec -it cli.org1.divvy.com bash
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

## Host queue

Containers run on the `network_divvy` Docker network. This allows containers to
communicate with each other on any ports where services are running,
by supplying `container_name` and a port number.

An exception to this is where the application container `web.app.divvy.com`
needs to tell the network a new user has signed up and to a new organisation
needs to be created. This is done by executing the `network.sh` script,
on the host.

To execute the host script from inside `web.app.divvy.com` we mount a named
pipe (FIFO) called `host_queue` (created during provisioning). The container
writes commands to `host_queue`, the commands are read and executed by the
host, via the `network/host-queue-processor.sh` script.
