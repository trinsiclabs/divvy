class LedgerItem {
  /**
   * Convert object to buffer containing JSON data serialisation
   * Typically used before putState() ledger API.
   *
   * @param {Object} JSON object to serialize
   *
   * @return {buffer} buffer with the data to store
   */
  static serialise(object) {
    return Buffer.from(JSON.stringify(object));
  }

  /**
   * Deserialise object into one of a set of supported JSON classes
   * i.e. Covert serialised data to JSON object
   * Typically used after getState() ledger API
   *
   * @param {data} data data to deserialise into JSON object
   * @param {object} supportedClasses the set of classes data can be serialised to
   *
   * @return {json} JSON with the data to store
   */
  static deserialise(data, supportedClasses) {
    const json = JSON.parse(data.toString());
    const objClass = supportedClasses[json.class];

    if (!objClass) {
        throw new Error(`Unknown class of ${json.class}`);
    }

    return new (objClass)(json);
  }

  /**
   * Deserialise object into specific object class
   * Typically used after getState() ledger API
   *
   * @param {data} data to deserialise into JSON object
   *
   * @return {json} JSON with the data to store
   */
  static deserialiseClass(data, objClass) {
    return new (objClass)(JSON.parse(data.toString()));
  }

  /**
   * Join the keyParts to make a unified string.
   *
   * @param {string[]} keyParts
   */
  static makeKey(keyParts) {
    return keyParts.map(part => JSON.stringify(part)).join(':');
  }

  static splitKey(key){
    return key.split(':');
  }

  constructor(ledgerItemClass, keyParts) {
    this.class = ledgerItemClass;
    this.key = LedgerItem.makeKey(keyParts);
  }

  getClass() {
    return this.class;
  }

  getKey() {
    return this.key;
  }

  getSplitKey(){
    return LedgerItem.splitKey(this.key);
  }

  serialize() {
    return LedgerItem.serialize(this);
  }
}

module.exports = LedgerItem;
