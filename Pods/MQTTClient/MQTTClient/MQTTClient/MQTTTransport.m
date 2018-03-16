//
//  MQTTTransport.m
//  MQTTClient
//
//  Created by Christoph Krey on 05.01.16.
//  Copyright © 2016-2017 Christoph Krey. All rights reserved.
//

#import "MQTTTransport.h"

#import "MQTTLog.h"

@implementation MQTTTransport
@synthesize state;
@synthesize queue;
@synthesize delegate;
@synthesize host;
@synthesize port;

- (instancetype)init {
    self = [super init];
    self.state = MQTTTransportCreated;
    return self;
}

- (void)open {
    DDLogError(@"MQTTTransport is abstract class");
}

- (void)close {
    DDLogError(@"MQTTTransport is abstract class");
}

- (BOOL)send:(NSData *)data {
    DDLogError(@"MQTTTransport is abstract class");
    return FALSE;
}

@end
