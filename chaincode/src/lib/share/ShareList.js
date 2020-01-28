const LedgerItemList = require('../ledger-api/LedgerItemList');
const Share = require('./Share');

class ShareList extends LedgerItemList {
  constructor(ctx) {
    super(ctx, 'com.divvy.sharelist');
    this.use(Share);
  }

  async addShare(share) {
    return this.addLedgerItem(share);
  }

  async getShare(key) {
    return this.getLedgerItem(key);
  }

  async updateShare(share) {
    return this.updateLedgerItem(share);
  }
}

module.exports = ShareList;
