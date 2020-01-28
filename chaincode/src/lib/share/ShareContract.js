const { Contract } = require('fabric-contract-api');
const ShareContext = require('./ShareContext');
const Share = require('./Share');

class ShareContract extends Contract {
  constructor() {
    super('com.divvy.share');
  }

  createContext() {
    return new ShareContext();
  }

  /**
   * Generate default items when the contract is instantiated.
   *
   * @param {Context} ctx the transaction context
   * @param {String} issuer share issuer
   */
  async instantiate(ctx, issuer) {
    for (let index = 0; index < 100; index += 1) {
      await this.issue(ctx, issuer, index + 1, Date.now(), 1.00);
    }
  }

  /**
   * Issue a share.
   *
   * @param {Context} ctx the transaction context
   * @param {String} issuer share issuer
   * @param {Integer} shareNumber share number for this issuer
   * @param {String} issueDateTime share issue date
   * @param {Integer} faceValue face value of share
   *
   * @return {Share}
   */
  async issue(ctx, issuer, shareNumber, issueDateTime, faceValue) {
    const share = Share.createInstance(issuer, shareNumber, issueDateTime, faceValue);

    share.setOwner(issuer);

    await ctx.shareList.addShare(share);

    return share;
  }

  /**
   * Move a share from one org to another.
   *
   * @param {Context} ctx the transaction context
   * @param {String} issuer share issuer
   * @param {Integer} shareNumber share number for this issuer
   * @param {String} currentOwner current owner of the share
   * @param {String} newOwner new owner of the share
   *
   * @return {Share}
   */
  async moveShare(ctx, issuer, shareNumber, currentOwner, newOwner) {
    const key = Share.makeKey([issuer, shareNumber]);
    const share = await ctx.shareList.getShare(key);

    // Validate the current owner.
    if (share.getOwner() !== currentOwner) {
      throw new Error(`Share ${issuer}${shareNumber} is not owned by ${currentOwner}.`);
    }

    share.setOwner(newOwner);

    await ctx.shareList.updateShare(share);

    return share;
  }

  async query(ctx) {

  }
}

module.exports = ShareContract;
