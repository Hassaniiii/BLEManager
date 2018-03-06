//
//  Manager.m
//  BLEManager
//
//  Created by Hassan Shahbazi on 6/20/17.
//  Copyright © 2017 Hassan Shahbazi. All rights reserved.
//

#import "CentralManager.h"

#define VANCOSYS_KEY    [[NSBundle mainBundle] bundleIdentifier]

@interface CentralManager()
@property (nonatomic, strong) CBCentralManager *manager;
@property (nonatomic, strong) CBPeripheral *periperal;
@property (nonatomic, strong) NSMutableArray *discoveredCharacterstics;
@end

@implementation CentralManager

- (id)init {
    self = [super init];
    if (self) {
        _discovery_RSSI_filter = -50;
        _discoveredCharacterstics = [NSMutableArray new];
        
        dispatch_queue_t queue = dispatch_queue_create("BLEManager.Central", DISPATCH_QUEUE_CONCURRENT);
        _manager = [[CBCentralManager alloc]
                    initWithDelegate:self queue: queue
                    options: @{CBCentralManagerOptionRestoreIdentifierKey: VANCOSYS_KEY,
                               CBCentralManagerOptionShowPowerAlertKey: @YES}];
    }
    return self;
    
}
+ (CentralManager *)instance {
    static CentralManager *singleton = nil;
    if (!singleton) {
        singleton = [CentralManager new];
    }
    return singleton;
}

- (void)connect {
    if (_periperal) {
        _periperal.delegate = self;
        [_manager connectPeripheral:_periperal options:nil];
    }
}
- (void)connect:(CBPeripheral *)peripheral {
    _periperal = peripheral;
    [self connect];
}

- (void)getPairedList {
    NSArray *pairedPeriperhals = [_manager retrieveConnectedPeripheralsWithServices:_service_UUID];
    [self centralManager:_manager didDiscoverPairedPeripherals: pairedPeriperhals];
}

- (void)disconnect {
    if (_periperal)
        [_manager cancelPeripheralConnection:_periperal];
}

- (void)scan {
    [self disconnect];
    [self stopScan];
    [_manager scanForPeripheralsWithServices:_service_UUID options:nil];
}

- (void)stopScan {
    [_manager stopScan];
}

- (void)readRSSI {
    [_periperal readRSSI];
}

- (void)read:(CBUUID *)Characterstic {
    for (CBCharacteristic *characterstic in _discoveredCharacterstics)
        if ([characterstic.UUID.UUIDString isEqualToString: Characterstic.UUIDString])
            [_periperal readValueForCharacteristic: characterstic];
}

- (void)write:(NSData *)data on:(CBUUID *)Characterstic {
    [self write:data on:Characterstic with:CBCharacteristicWriteWithResponse];
}
- (void)write:(NSData *)data on:(CBUUID *)Characterstic with:(CBCharacteristicWriteType )type {
    for (CBCharacteristic *characterstic in _discoveredCharacterstics)
        if ([characterstic.UUID.UUIDString isEqualToString: Characterstic.UUIDString])
            [_periperal writeValue: data
                 forCharacteristic: characterstic
                              type: type];
}

- (NSString *)connectedCentralAddress {
    return _periperal.identifier.UUIDString;
}

#pragma mark - Cache Connected Peripheral
- (void)Save:(NSString *)peripheralMac {
    [[NSUserDefaults standardUserDefaults] setValue:peripheralMac forKey:VANCOSYS_KEY];
    [[NSUserDefaults standardUserDefaults] synchronize];
}
- (NSString *)GetPeripheralMac {
    return [[NSUserDefaults standardUserDefaults] objectForKey:VANCOSYS_KEY];
}
- (void)RemoveSavedPeripheralMac {
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:VANCOSYS_KEY];
}

#pragma mark - Central Manager Delegate
- (void)centralManagerDidUpdateState:(CBCentralManager *)central {
    NSMutableDictionary *userInfo = [[NSMutableDictionary alloc] init];
    [userInfo setObject:[NSNumber numberWithInt:central.state] forKey:@"State"];
    
    [[NSNotificationCenter defaultCenter] postNotificationName:CN_StateUpdate object:nil userInfo: userInfo];
}
- (void)centralManager:(CBCentralManager *)central didDiscoverPeripheral:(CBPeripheral *)peripheral advertisementData:(NSDictionary<NSString *,id> *)advertisementData RSSI:(NSNumber *)RSSI {
    _manager = central;
    _periperal = peripheral;
    _periperal.delegate = self;
    
    if (RSSI.integerValue > _discovery_RSSI_filter && RSSI.integerValue < 0) {
        NSMutableDictionary *userInfo = [[NSMutableDictionary alloc] init];
        [userInfo setObject:peripheral.identifier.UUIDString forKey:@"MacAddress"];
        
        [[NSNotificationCenter defaultCenter] postNotificationName:CN_didFound object:nil userInfo: userInfo];
    }
}
- (void)centralManager:(CBCentralManager *)central didConnectPeripheral:(CBPeripheral *)peripheral {
    [self Save: peripheral.identifier.UUIDString];
    [central stopScan];
    
    [_periperal discoverServices: _service_UUID];
    [[NSNotificationCenter defaultCenter] postNotificationName:CN_didConnect object:nil];
}
- (void)centralManager:(CBCentralManager *)central didFailToConnectPeripheral:(CBPeripheral *)peripheral error:(NSError *)error {
    NSMutableDictionary *userInfo = [[NSMutableDictionary alloc] init];
    [userInfo setObject:error.localizedDescription forKey:@"Error"];
    
    [[NSNotificationCenter defaultCenter] postNotificationName:CN_didFailed object:nil userInfo: userInfo];
}
- (void)centralManager:(CBCentralManager *)central didDisconnectPeripheral:(CBPeripheral *)peripheral error:(NSError *)error {
    [self RemoveSavedPeripheralMac];
    [[NSNotificationCenter defaultCenter] postNotificationName:CN_didDisconnect object:nil];
}
- (void)centralManager:(CBCentralManager *)central willRestoreState:(NSDictionary<NSString *,id> *)dict {
    NSArray *restoredPeripherals = [dict valueForKey: CBCentralManagerRestoredStatePeripheralsKey];
    if (restoredPeripherals)
        for (CBPeripheral *peripheral in restoredPeripherals)
            if ([peripheral.identifier.UUIDString isEqualToString:[self GetPeripheralMac]]) {
                _manager = central;
                _periperal = peripheral;
                _periperal.delegate = self;
                [[NSNotificationCenter defaultCenter] postNotificationName:CN_didRestored object:nil];
            }
}
- (void)centralManager:(CBCentralManager *)central didDiscoverPairedPeripherals:(NSArray *)peripherals {
    _manager = central;
    
    NSMutableDictionary *userInfo = [[NSMutableDictionary alloc] init];
    [userInfo setObject:peripherals forKey:@"PairedList"];
    
    [[NSNotificationCenter defaultCenter] postNotificationName:CN_PairedList object:nil userInfo: userInfo];
}

#pragma mark - Peripheral Delegate
- (void)peripheralDidUpdateName:(CBPeripheral *)peripheral {}
- (void)peripheral:(CBPeripheral *)peripheral didDiscoverServices:(NSError *)error {
    for (CBService *service in peripheral.services) {
        if ([_service_UUID containsObject: service.UUID]) {
            [peripheral discoverCharacteristics:_service_characteristic forService:service];
            [peripheral discoverCharacteristics:_service_notifyCharacteristic forService:service];
        }
    }
}
- (void)peripheral:(CBPeripheral *)peripheral didReadRSSI:(NSNumber *)RSSI error:(NSError *)error {
    NSMutableDictionary *userInfo = [[NSMutableDictionary alloc] init];
    [userInfo setObject:[NSNumber numberWithInt:RSSI.intValue] forKey:@"RSSIValue"];
    
    [[NSNotificationCenter defaultCenter] postNotificationName:CN_didReadRSSI object:nil userInfo: userInfo];
}
- (void)peripheral:(CBPeripheral *)peripheral didWriteValueForDescriptor:(CBDescriptor *)descriptor error:(NSError *)error {}
- (void)peripheral:(CBPeripheral *)peripheral didDiscoverCharacteristicsForService:(CBService *)service error:(NSError *)error {
    for (CBCharacteristic *characteristic in service.characteristics) {
        BOOL duplicatedCharacterstic = false;
        for (CBCharacteristic *discovered in _discoveredCharacterstics)
            if ([discovered.UUID isEqual: characteristic.UUID])
                duplicatedCharacterstic = true;
        if (!duplicatedCharacterstic)
            [_discoveredCharacterstics addObject: characteristic];
        if ([_service_notifyCharacteristic containsObject:characteristic.UUID])
            [peripheral setNotifyValue:YES forCharacteristic:characteristic];
    }
}
- (void)peripheral:(CBPeripheral *)peripheral didModifyServices:(NSArray<CBService *> *)invalidatedServices {}
- (void)peripheral:(CBPeripheral *)peripheral didUpdateValueForDescriptor:(CBDescriptor *)descriptor error:(NSError *)error {}
- (void)peripheral:(CBPeripheral *)peripheral didWriteValueForCharacteristic:(CBCharacteristic *)characteristic error:(NSError *)error {
    [[NSNotificationCenter defaultCenter] postNotificationName:CN_didWriteData object:nil];
}
- (void)peripheral:(CBPeripheral *)peripheral didUpdateValueForCharacteristic:(CBCharacteristic *)characteristic error:(NSError *)error {
    if (characteristic.value) {
        NSMutableDictionary *userInfo = [[NSMutableDictionary alloc] init];
        [userInfo setObject:characteristic.value forKey:@"Data"];
        
        [[NSNotificationCenter defaultCenter] postNotificationName:CN_didReadData object:nil userInfo: userInfo];
    }
}
- (void)peripheral:(CBPeripheral *)peripheral didDiscoverIncludedServicesForService:(CBService *)service error:(NSError *)error {}
- (void)peripheral:(CBPeripheral *)peripheral didDiscoverDescriptorsForCharacteristic:(CBCharacteristic *)characteristic error:(NSError *)error {}
- (void)peripheral:(CBPeripheral *)peripheral didUpdateNotificationStateForCharacteristic:(CBCharacteristic *)characteristic error:(NSError *)error {}

@end

