const { Contract } = require('fabric-contract-api');
const shim = require('fabric-shim');

class EquityContract extends Contract {
  constructor() {
    super('com.divvy.equity');
  }

  async instantiate(ctx) {
    return shim.success();
  }

  /**
   * Preload data into the ledger.s
   */
  async populateDefaults(ctx) {

  }

  /**
   * Move equity from one org to another.
   */
  async moveEquity(ctx, fromOrg, toOrg) {

  }

  /**
   * Query equity on one org.
   */
  async queryOrgEquity(ctx, org) {

  }

  /**
   * Query equity across all orgs on the channel.
   */
  async queryAllEquity(ctx) {

  }
}

module.exports = EquityContract;
