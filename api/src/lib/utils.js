const { FileSystemWallet } = require('fabric-network');
const path = require('path');

function getConnectionProfilePath(org) {
  return path.resolve(__dirname, '..', '..', 'org-config', org, 'connection-profile.json');
}

function getWalletPath(org) {
  return path.resolve(__dirname, '..', 'wallet', org);
}

function getWallet(org) {
  return new FileSystemWallet(getWalletPath(org));
}

module.exports = {
  getConnectionProfilePath,
  getWalletPath,
  getWallet
};
