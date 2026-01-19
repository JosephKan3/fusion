-------------------------------------------------------
------------            me_interface            -------------
-------------------------------------------------------
*****************************************************
clearInterfacePatternOutput : function(slot:number, index:number):boolean -- Clear pattern output at the given index.
*****************************************************
getItemsInNetworkById : function(filter:table):table -- Get a list of the stored items in the network matching the filter. Filter is an Array of Item IDs
*****************************************************
allItems : function():userdata -- Get an iterator object for the list of the items in the network.
*****************************************************
getIdlePowerUsage : function():number -- Get the idle power usage of the network.
*****************************************************
getMaxStoredPower : function():number -- Get the maximum stored power in the network.
*****************************************************
getCpus : function():table -- Get a list of tables representing the available CPUs in the network.
*****************************************************
clearInterfacePatternInput : function(slot:number, index:number):boolean -- Clear pattern input at the given index.
*****************************************************
getInterfaceConfiguration : function([slot:number]):table -- Get the configuration of the interface.
*****************************************************
getAvgPowerUsage : function():number -- Get the average power usage of the network.
*****************************************************
getCraftables : function([filter:table]):table -- Get a list of known item recipes. These can be used to issue crafting requests.
*****************************************************
setInterfacePatternInput : function(slot:number, database:address, entry:number, size:number, index:number):boolean -- Set the pattern input at the given index.
*****************************************************
storeInterfacePatternInput : function(slot:number, index:number, database:address, entry:number):boolean -- Store pattern input at the given index to the database entry.
*****************************************************
storeInterfacePatternOutput : function(slot:number, index:number, database:address, entry:number):boolean -- Store pattern output at the given index to the database entry.
*****************************************************
getItemInNetwork : function(name:string[, damage:number[, nbt:string]]):table -- Retrieves the stored item in the network by its unlocalized name.
*****************************************************
getItemsInNetwork : function([filter:table]):table -- Get a list of the stored items in the network.
*****************************************************
getAvgPowerInjection : function():number -- Get the average power injection into the network.
*****************************************************
setInterfaceConfiguration : function([slot:number][, database:address, entry:number[, size:number]]):boolean -- Configure the interface.
*****************************************************
getInterfacePattern : function([slot:number]):table -- Get the given pattern in the interface.
*****************************************************
getFluidsInNetwork : function():table -- Get a list of the stored fluids in the network.
*****************************************************
getStoredPower : function():number -- Get the stored power in the network. 
*****************************************************
setInterfacePatternOutput : function(slot:number, database:address, entry:number, size:number, index:number):boolean -- Set the pattern output at the given index.
*****************************************************
getEssentiaInNetwork : function():table -- Get a list of the stored essentia in the network.
*****************************************************
store : function(filter:table, dbAddress:string[, startSlot:number[, count:number]]): Boolean -- Store items in the network matching the specified filter in the database with the specified address.
*****************************************************
