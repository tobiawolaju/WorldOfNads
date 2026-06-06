Features:
This contract holds the 20 MON for the loot box.
stealBox(): This is the high-frequency function. Every time it’s called, it subtracts the gas cost from the internal balance and changes the currentOwner.
This should be a separate contract so that a bug in the Loot Box doesn't break the main Match Engine.
