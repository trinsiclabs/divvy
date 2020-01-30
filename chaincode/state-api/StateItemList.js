const StateItem = require('./StateItem');

/**
 * StateItemList provides a named virtual container for a set of StateItems.
 * Each item has a unique key which associates it with the container, rather
 * than the container containing a link to the item. This minimizes collisions
 * for parallel transactions on different items.
 */
class StateItemList {
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
   * StateItem object is serialised before writing.
   */
  async addStateItem(item) {
    const key = this.ctx.stub.createCompositeKey(this.name, item.getSplitKey());
    const data = StateItem.serialise(item);

    await this.ctx.stub.putState(key, data);
  }

  /**
   * Get a StateItem from the list using supplied keys. Form composite
   * keys to retrieve item from world state. StateItem data is deserialised
   * into JSON object before being returned.
   */
  async getStateItem(key) {
    const stateKey = this.ctx.stub.createCompositeKey(this.name, StateItem.splitKey(key));
    const data = await this.ctx.stub.getState(stateKey);

    if (data && data.toString('utf8')) {
      return StateItem.deserialise(data, this.supportedClasses);
    }

    return null;
  }

  /**
   * Update a item in the list. Puts the new item in world state with
   * appropriate composite key. Note that item defines its own key.
   * An item is serialised before writing. Logic is very similar to
   * addStateItem() but kept separate because it is semantically distinct.
   */
  async updateStateItem(item) {
    const key = this.ctx.stub.createCompositeKey(this.name, item.getSplitKey());
    const data = StateItem.serialise(item);

    await this.ctx.stub.putState(key, data);
  }

  /**
   * Stores the class for future deserialisation
   */
  use(itemClass) {
    this.supportedClasses[itemClass.getClass()] = itemClass;
  }
}

module.exports = StateItemList;
