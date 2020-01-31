#!/usr/bin/env node

const { Gateway } = require('fabric-network');
const { getConnectionProfilePath, getWallet } = require ('./utils');

const argv = require('yargs')
  .usage('Usage: $0 -o <org> -u <user> -c <channel> -n <contract> -m <method> -a <args>')
  .demandOption(['o','u','c','n','m'])
  .help('help')
  .argv;

async function main() {
  try {
    const connectionProfilePath = getConnectionProfilePath(argv.o);

    // Create a new file system based wallet for managing identities.
    const wallet = getWallet(argv.o);

    // Check to see if we've already enrolled the user.
    const userExists = await wallet.exists(argv.u);
    if (!userExists) {
      console.log(`An identity for the user "${argv.u}" does not exist in the wallet.`);
      console.log(`Run "node security.js registeruser ${argv.o} ${argv.u}" before retrying.`);
      return;
    }

    // Create a new gateway for connecting to our peer node.
    const gateway = new Gateway();
    await gateway.connect(connectionProfilePath, { wallet, identity: argv.u, discovery: { enabled: true, asLocalhost: false } });

    // Get the network (channel) our contract is deployed to.
    const network = await gateway.getNetwork(argv.c);

    // Get the contract from the network.
    const contract = network.getContract(argv.n);

    // Evaluate the specified transaction.
    // queryCar transaction - requires 1 argument, ex: ('queryCar', 'CAR4')
    // queryAllCars transaction - requires no arguments, ex: ('queryAllCars')
    const args = argv.a ? JSON.parse(argv.a) : [];
    const result = await contract.evaluateTransaction(argv.m, ...args);
    console.log(result.toString());
  } catch (error) {
    console.error(`Failed to evaluate transaction: ${error}`);
    process.exit(1);
  }
}

main();
