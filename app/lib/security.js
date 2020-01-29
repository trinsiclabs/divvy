#!/usr/bin/env node

const FabricCAServices = require('fabric-ca-client');
const { Gateway, FileSystemWallet, X509WalletMixin } = require('fabric-network');
const fs = require('fs');
const path = require('path');

require('yargs')
  .usage('Usage: $0 <command> [options]')
  .command(
    'enrolladmin <org>',
    'enroll an orgs admin user',
    yargs => {},
    argv => {
      enrollOrg(argv.org);
    }
  )
  .command(
    'registeruser <org> <user>',
    'register a user under an org',
    yargs => {},
    argv => {
      registerUser(argv.org, argv.user);
    }
  )
  .help('help')
  .argv;

function getConnectionProfilePath(org) {
  return path.resolve(__dirname, '..', '..', 'org-config', org, 'connection-profile.json');
}

function getWalletPath(org) {
  return path.resolve(__dirname, '..', 'wallet', org);
}

function getWallet(org) {
  return new FileSystemWallet(getWalletPath(org));
}

/**
 * When we created the organisation, an admin user — literally called admin —
 * was created as the registrar for the certificate authority (CA).
 * This function generates the private key, public key,
 * and X.509certificate for admin.
 *
 * This process uses a Certificate Signing Request (CSR) — the private and
 * public key are first generated locally and the public key is then sent
 * to the CA which returns an encoded certificate for use by the application.
 * These three credentials are then stored in the wallet, allowing us to act
 * as an administrator for the CA.
 *
 * @param {string} org
 */
async function enrollOrg(org) {
  try {
    const connectionProfilePath = getConnectionProfilePath(org);
    const connectionProfileJson = fs.readFileSync(connectionProfilePath, 'utf8');
    const connectionProfile = JSON.parse(connectionProfileJson);

    // Create a new CA client for interacting with the CA.
    const caInfo = connectionProfile.certificateAuthorities[`ca.${org}.divvy.com`];
    const caTLSCACerts = caInfo.tlsCACerts.pem;
    const ca = new FabricCAServices(caInfo.url, { trustedRoots: caTLSCACerts, verify: false }, caInfo.caName);

    // Create a new file system based wallet for managing identities.
    const wallet = getWallet(org);

    // Check to see if we've already enrolled the admin user.
    const adminExists = await wallet.exists('admin');
    if (adminExists) {
        console.log('An identity for the admin user "admin" already exists in the wallet');
        return;
    }

    // Enroll the admin user, and import the new identity into the wallet.
    const enrollment = await ca.enroll({ enrollmentID: 'admin', enrollmentSecret: 'adminpw' });
    const identity = X509WalletMixin.createIdentity(`${org}-msp`, enrollment.certificate, enrollment.key.toBytes());
    await wallet.import('admin', identity);
    console.log('Successfully enrolled admin user "admin" and imported it into the wallet');
  } catch (error) {
    console.error(`Failed to enroll admin user "admin": ${error}`);
    process.exit(1);
  }
}

/**
 * Similar to the enrollOrg function, this function uses a CSR to enroll a user
 * and store their credentials alongside those of admin in the wallet.
 *
 * @param {string} org
 * @param {string} user
 */
async function registerUser(org, user) {
  try {
    const connectionProfilePath = getConnectionProfilePath(org);

    // Create a new file system based wallet for managing identities.
    const wallet = getWallet(org);

    // Check to see if we've already enrolled the admin user.
    const adminExists = await wallet.exists('admin');
    if (!adminExists) {
      console.log('An identity for the admin user "admin" does not exist in the wallet');
      console.log(`Run 'node security.js enrolladmin ${org}' application before retrying`);
      return;
    }

    // Create a new gateway for connecting to our peer node.
    const gateway = new Gateway();
    await gateway.connect(connectionProfilePath, { wallet, identity: 'admin', discovery: { enabled: true, asLocalhost: true } });

    // Get the CA client object from the gateway for interacting with the CA.
    const ca = gateway.getClient().getCertificateAuthority();
    const adminIdentity = gateway.getCurrentIdentity();

    // Register the user, enroll the user, and import the new identity into the wallet.
    const secret = await ca.register({ enrollmentID: user, role: 'client' }, adminIdentity);
    const enrollment = await ca.enroll({ enrollmentID: user, enrollmentSecret: secret });
    const userIdentity = X509WalletMixin.createIdentity(`${org}-msp`, enrollment.certificate, enrollment.key.toBytes());
    await wallet.import(user, userIdentity);
    console.log(`Successfully registered and enrolled admin user "${user}" and imported it into the wallet`);

  } catch (error) {
    console.error(error);
    process.exit(1);
  }
}
