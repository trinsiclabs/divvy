const LedgerItem = require('../ledger-api/LedgerItem');

class Share extends LedgerItem {
  static fromBuffer(buffer) {
    return Share.deserialize(buffer);
  }

  /**
   * Deserialise item data to a share.
   *
   * @param {Buffer} data to form back into the object
   */
  static deserialize(data) {
    return LedgerItem.deserializeClass(data, Share);
  }

  /**
   * Factory method to create a share object
   */
  static createInstance(issuer, shareNumber, issueDateTime, faceValue) {
    return new Share({ issuer, shareNumber, issueDateTime, faceValue });
  }

  static getClass() {
    return 'com.divvy.share';
  }

  constructor(obj) {
    super(Share.getClass(), [obj.issuer, obj.shareNumber]);
    Object.assign(this, obj);
  }

  getIssuer() {
    return this.issuer;
  }

  setIssuer(newIssuer) {
    this.issuer = newIssuer;
  }

  getOwner() {
    return this.owner;
  }

  setOwner(newOwner) {
    this.owner = newOwner;
  }

  toBuffer() {
    return Buffer.from(JSON.stringify(this));
  }
}

module.exports = Share;
