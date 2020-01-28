const { Context } = require('fabric-contract-api');
const ShareList = require('./ShareList');

class ShareContext extends Context {
  constructor() {
    super();
    this.shareList = new ShareList(this);
  }
}

module.exports = ShareContext;
