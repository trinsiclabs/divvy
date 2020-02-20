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
added to the network creates three more containers:

* ca.ORG_NAME.divvy.com
* peer.ORG_NAME.divvy.com
* cli.ORG_NAME.divvy.com

See the [network docs](https://github.com/flashbackzoo/divvy-network)
for more info.

#### Chaincode

Chaincode is used by network peers to query and update ledger state.

See the [chaincode docs](https://github.com/flashbackzoo/divvy-chaincode)
for more info.

#### Application

Primary user interface (UI) for interacting with the network.
Users can signup (create an organisation), join channels,
and trade shares using the app.

See the [application docs](https://github.com/flashbackzoo/divvy-application)
for more info.

#### API

The API component connects the client app to the network.

See the [API docs](https://github.com/flashbackzoo/divvy-api) for ore info.

### Stand up the host

Once you have installed the prerequisites you're ready to
stand up and provision the host VM.

```
$ vagrant up
```

This will download the `ubuntu/bionic64` image (if you don't have it already)
and provision the box with various tools. The provisioning script is in
`Vagrantfile` if you want to see exactly what happens.

Once that finishes, login to the host:

```
$ vagrant ssh
```

### Bring the network up

From the `network` directory:

```
$ ./network.sh up
```

This brings up a skeleton network consisting of an order and CA.
Logging information is streamed to this window, so open a new terminal window,
and keep this one open as well so you can see the logs.

### Populate the network

In your new terminal window add a couple of organisations to the network.
This is done from the `web.app.divvy.com` container to simulate a request
from the application.

```
$ sudo docker exec -it web.app.divvy.com bash
```

Create the first organisation:

```
$ echo "./organisation.sh create --org org1 --pport 8051 --ccport 8052 --caport 8053" > host_queue
```

Create the second organisation:

```
$ echo "./organisation.sh create --org org2 --pport 9051 --ccport 9052 --caport 9053" > host_queue
```

### Join a channel

While still in the application container, join org2 to the org1 channel:

```
$ echo "./organisation.sh joinchannel --org org2 --channelowner org1" > host_queue
```

Now exit the application container:

```
$ exit
```

### Make a trade

Log into the org1 cli container:

```
$ sudo docker exec -it cli.org1.divvy.com bash
```

See the current height and hash of the org1 blockchain:

```
$ peer channel getinfo -c org1-channel
```

Transfer ownership of a share from org1 to org2:

```
$ peer chaincode invoke -C org1-channel -n share -c '{"Args":["com.divvy.share:changeShareOwner","org1","1","org1","org2"]}' --tls --cafile /opt/gopath/src/github.com/hyperledger/fabric/orderer/msp/tlscacerts/tlsca.divvy.com-cert.pem
```

See the new height and hash of the org1 blockchain:

```
$ peer channel getinfo -c org1-channel
```

Verify the share has changed ownership:

```
$ peer chaincode query -C org1-channel -n share -c '{"Args":["com.divvy.share:queryShare","org1","1"]}'
```

## Host queue

Containers run on the `network_divvy` Docker network. This allows containers to
communicate with each other on any ports where services are available,
by supplying `container_name` and a port number.

An exception to this is where the application container `web.app.divvy.com`
needs to tell the network a new user has registered and to create a new
organisation (by executing the `network.sh` script, on the host).

To execute the host script from inside `web.app.divvy.com` we mount a named
pipe (FIFO) called `host_queue` (created during provisioning). The container
writes commands to `host_queue` and the commands are read then executed
by the host.

The process to read the pipe is created and killed by the `network.sh up` and
`network.sh down` commands respectively.

## Development

During provisioning each platform component is cloned onto the host VM. To make
changes to components you to connect your IDE to the host. Here's how to do it
using [Visual Studio Code](https://code.visualstudio.com/).

Install the
[Remote SSH plugin](https://marketplace.visualstudio.com/items?itemName=ms-vscode-remote.remote-ssh)

Bring up the host if you haven't already:

```
$ vagrant up
```

Print and copy the Vagrant SSH config:

```
$ vagrant ssh-config
```

Configure the Remote SSH plugin:

1. Open Visual Studio Code
2. Open the Remote SSH plugin (bottom left corner)
3. Select 'Open configuration file...'
4. Select 'YOUR_HOME_DIR/.ssh/config'
5. Paste the Vagrant SSH config
6. Close the file

Now connect to the host VM:

1. Open the Remote SSH plugin again
2. Select 'Connect to host...'
3. Select 'divvy'

A new editor window should open with your remote connection.

### Gotchas

Here's a few things to look out for along the way...

#### Destorying the host VM

VMs are great because you can mess stuff up, blow away the machine,
and start again. Because this project clones repos (code you're working on)
into the VM, you have to be a bit careful when destroying the VM.

When you destroy the VM you're also destroying your code. Always push your
changes back upstream before destroying the host VM.

#### Commit signing

If you try to commit changes and see:

```
error: gpg failed to sign the data
```

Support for signing commits is currently not implemented. You need to edit
`.gitconfig` on the host VM and set the flag to `false`.
