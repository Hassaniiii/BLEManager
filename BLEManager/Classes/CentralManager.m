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
@property (nonatomic, strong) CBCentralManager *centralManager;
@property (nonatomic, strong) CBCentralManager *localCentral;
@property (nonatomic, strong) CBPeripheral *localPeriperal;
@property (nonatomic, strong) NSMutableArray *discoveredCharacterstics;
@property (nonatomic, strong) NSString *connectedMacAddress;
@property (nonatomic, assign) BOOL isRestored;
@end

@implementation CentralManager

- (id)init {
    self = [super init];
    if (self) {
        _connectedMacAddress = @"";
        _RSSI_filter = -50;
        _discoveredCharacterstics = [NSMutableArray new];
        _isRestored = NO;
        
        dispatch_queue_t centralQueu = dispatch_queue_create("com.Vancosys", NULL);
        _centralManager = [[CBCentralManager alloc]
                           initWithDelegate:self
                           queue:centralQueu
                           options: @{CBCentralManagerOptionRestoreIdentifierKey:VANCOSYS_KEY,
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
    [_localCentral connectPeripheral:_localPeriperal options:nil];
}

- (void)getPairedList {
    [self centralManager:_centralManager didDiscoverPairedPeripherals:
     [_centralManager retrieveConnectedPeripheralsWithServices:_service_UUID]];
}

- (void)disconnect {
    [_localCentral cancelPeripheralConnection:_localPeriperal];
}

- (void)scan {
    [self disconnect];
    [self stopScan];
    [_centralManager scanForPeripheralsWithServices:_service_UUID options:nil];
}

- (void)stopScan {
    [_centralManager stopScan];
}

- (void)readRSSI {
    [_localPeriperal readRSSI];
}

- (void)read:(CBUUID *)Characterstic {
    for (CBCharacteristic *characterstic in _discoveredCharacterstics)
        if ([characterstic.UUID.UUIDString isEqualToString: Characterstic.UUIDString])
            [_localPeriperal readValueForCharacteristic: characterstic];
}

- (void)write:(NSData *)data on:(CBUUID *)Characterstic {
    for (CBCharacteristic *characterstic in _discoveredCharacterstics)
        if ([characterstic.UUID.UUIDString isEqualToString: Characterstic.UUIDString])
            [_localPeriperal writeValue: data
                      forCharacteristic: characterstic
                                   type: CBCharacteristicWriteWithResponse];
}

- (NSString *)connectedCentralAddress {
    return _connectedMacAddress;
}

#pragma mark - Cache Connected Peripheral
- (void)Save:(NSString *)peripheralMac {
    _connectedMacAddress = peripheralMac;
    [[NSUserDefaults standardUserDefaults] setValue:peripheralMac forKey:VANCOSYS_KEY];
    [[NSUserDefaults standardUserDefaults] synchronize];
}
- (NSString *)GetPeripheralMac {
    return [[NSUserDefaults standardUserDefaults] objectForKey:VANCOSYS_KEY];
}
- (void)RemoveSavedPeripheralMac {
    _connectedMacAddress = @"";
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:VANCOSYS_KEY];
}

#pragma mark - Central Manager Delegate
- (void)centralManagerDidUpdateState:(CBCentralManager *)central {
    if ([_delegate respondsToSelector:@selector(BLECentralManagerStateDidUpdate:isRestored:)])
        [_delegate BLECentralManagerStateDidUpdate:central.state isRestored:_isRestored];
    _isRestored = NO;
}
- (void)centralManager:(CBCentralManager *)central didDiscoverPeripheral:(CBPeripheral *)peripheral advertisementData:(NSDictionary<NSString *,id> *)advertisementData RSSI:(NSNumber *)RSSI {
    _localCentral = central;
    _localPeriperal = peripheral;
    _localPeriperal.delegate = self;
    
    if (RSSI.integerValue > _RSSI_filter && RSSI.integerValue < 0) {
        if ([_delegate respondsToSelector:@selector(BLECentralManagerDidFind:)])
            [_delegate BLECentralManagerDidFind:peripheral.identifier.UUIDString];
    }
}
- (void)centralManager:(CBCentralManager *)central didConnectPeripheral:(CBPeripheral *)peripheral {
    _connectedMacAddress = peripheral.identifier.UUIDString;
    [central stopScan];
    
    [_localPeriperal discoverServices: _service_UUID];
    if ([_delegate respondsToSelector:@selector(BLECentralManagerDidConnect)])
        [_delegate BLECentralManagerDidConnect];
}
- (void)centralManager:(CBCentralManager *)central didFailToConnectPeripheral:(CBPeripheral *)peripheral error:(NSError *)error {
    if ([_delegate respondsToSelector:@selector(BLECentralManagerDidFail:)])
        [_delegate BLECentralManagerDidFail:error.localizedDescription];
}
- (void)centralManager:(CBCentralManager *)central didDisconnectPeripheral:(CBPeripheral *)peripheral error:(NSError *)error {
    _connectedMacAddress = @"";
    if ([_delegate respondsToSelector:@selector(BLECentralManagerDidDisconnect)])
        [_delegate BLECentralManagerDidDisconnect];
}
- (void)centralManager:(CBCentralManager *)central willRestoreState:(NSDictionary<NSString *,id> *)dict {
    NSArray *restoredPeripherals = [dict valueForKey: CBCentralManagerRestoredStatePeripheralsKey];
    if (restoredPeripherals)
        for (CBPeripheral *peripheral in restoredPeripherals)
            if (peripheral.identifier.UUIDString == [self GetPeripheralMac]) {
                _localCentral = central;
                _localPeriperal = peripheral;
                _localPeriperal.delegate = self;
                _isRestored = YES;
            }
}
- (void)centralManager:(CBCentralManager *)central didDiscoverPairedPeripherals:(NSArray *)peripherals {
    _localCentral = central;
    _localPeriperal = [peripherals firstObject];
    _localPeriperal.delegate = self;
    
    if ([_delegate respondsToSelector:@selector(BLECentralManagerDidGetPaired:)])
        [_delegate BLECentralManagerDidGetPaired:peripherals];
}

#pragma mark - Peripheral Delegate
- (void)peripheralDidUpdateName:(CBPeripheral *)peripheral {
    
}
- (void)peripheral:(CBPeripheral *)peripheral didDiscoverServices:(NSError *)error {
    for (CBService *service in peripheral.services) {
        if ([_service_UUID containsObject: service.UUID])
            [peripheral discoverCharacteristics:_service_characteristic forService:service];
    }
}
- (void)peripheral:(CBPeripheral *)peripheral didReadRSSI:(NSNumber *)RSSI error:(NSError *)error {
    if ([_delegate respondsToSelector:@selector(BLECentralManagerDidReadRSSI:)])
        [_delegate BLECentralManagerDidReadRSSI: RSSI.integerValue];
}
- (void)peripheral:(CBPeripheral *)peripheral didWriteValueForDescriptor:(CBDescriptor *)descriptor error:(NSError *)error {
}
- (void)peripheral:(CBPeripheral *)peripheral didDiscoverCharacteristicsForService:(CBService *)service error:(NSError *)error {
    for (CBCharacteristic *characteristic in service.characteristics) {
        [_discoveredCharacterstics addObject:characteristic];
        if ([_service_notifyCharacteristic containsObject:characteristic.UUID])
            [peripheral setNotifyValue:YES forCharacteristic:characteristic];
    }
}
- (void)peripheral:(CBPeripheral *)peripheral didModifyServices:(NSArray<CBService *> *)invalidatedServices {
    
}
- (void)peripheral:(CBPeripheral *)peripheral didUpdateValueForDescriptor:(CBDescriptor *)descriptor error:(NSError *)error {
    
}
- (void)peripheral:(CBPeripheral *)peripheral didWriteValueForCharacteristic:(CBCharacteristic *)characteristic error:(NSError *)error {
    if ([_delegate respondsToSelector:@selector(BLECentralManagerDidTransferData)])
        [_delegate BLECentralManagerDidTransferData];
}
- (void)peripheral:(CBPeripheral *)peripheral didUpdateValueForCharacteristic:(CBCharacteristic *)characteristic error:(NSError *)error {
    if ([_delegate respondsToSelector:@selector(BLECentralManagerDidRecieve:)])
        [_delegate BLECentralManagerDidRecieve: characteristic.value];
}
- (void)peripheral:(CBPeripheral *)peripheral didDiscoverIncludedServicesForService:(CBService *)service error:(NSError *)error {
    
}
- (void)peripheral:(CBPeripheral *)peripheral didDiscoverDescriptorsForCharacteristic:(CBCharacteristic *)characteristic error:(NSError *)error {
    
}
- (void)peripheral:(CBPeripheral *)peripheral didUpdateNotificationStateForCharacteristic:(CBCharacteristic *)characteristic error:(NSError *)error {
    
}

@end

