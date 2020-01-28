const LedgerItem = require('./LedgerItem.js');

/**
 * LedgerItemList provides a named virtual container for a set of ledger items.
 * Each item has a unique key which associates it with the container, rather
 * than the container containing a link to the item. This minimizes collisions
 * for parallel transactions on different items.
 */
class LedgerItemList {
  /**
   * Store Fabric context for subsequent API access, and name of list
   */
  constructor(ctx, listName) {
    this.ctx = ctx;
    this.name = listName;
    this.supportedClasses = {};
  }

  /**
   * Add an item to the list. Creates a new item in worldstate with
   * appropriate composite key. Note that item defines its own key.
   * LedgerItem object is serialised before writing.
   */
  async addLedgerItem(item) {
    const key = this.ctx.stub.createCompositeKey(this.name, item.getSplitKey());
    const data = LedgerItem.serialise(item);

    await this.ctx.stub.putState(key, data);
  }

  /**
   * Get a LedgerItem from the list using supplied keys. Form composite
   * keys to retrieve item from world state. LedgerItem data is deserialised
   * into JSON object before being returned.
   */
  async getLedgerItem(key) {
    const ledgerKey = this.ctx.stub.createCompositeKey(this.name, LedgerItem.splitKey(key));
    const data = await this.ctx.stub.getState(ledgerKey);

    if (data && data.toString('utf8')) {
      return LedgerItem.deserialise(data, this.supportedClasses);
    }

    return null;
  }

  /**
   * Update a item in the list. Puts the new item in world state with
   * appropriate composite key. Note that item defines its own key.
   * An item is serialised before writing. Logic is very similar to
   * addLedgerItem() but kept separate because it is semantically distinct.
   */
  async updateLedgerItem(item) {
    const key = this.ctx.stub.createCompositeKey(this.name, item.getSplitKey());
    const data = LedgerItem.serialise(item);

    await this.ctx.stub.putState(key, data);
  }

  /**
   * Stores the class for future deserialisation
   */
  use(itemClass) {
    this.supportedClasses[itemClass.getClass()] = itemClass;
  }
}

module.exports = LedgerItemList;
