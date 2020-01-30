const StateItemList = require('../../state-api/StateItemList');
const Share = require('./Share');

class ShareList extends StateItemList {
  constructor(ctx) {
    super(ctx, 'com.divvy.sharelist');
    this.use(Share);
  }

  async addShare(share) {
    return this.addStateItem(share);
  }

  async getShare(key) {
    return this.getStateItem(key);
  }

  async updateShare(share) {
    return this.updateStateItem(share);
  }
}

module.exports = ShareList;
