//
//  LLWS.m
//  Lightweight Limited Web Server
//
//  Created by Ross Tulloch on 5/08/11.
//  Copyright 2011 Ross Tulloch. All rights reserved.
//
//  Inspired by http://cocoawithlove.com/2009/07/simple-extensible-http-server-in-cocoa.html.
//  But all the bugs are mine.
//
/*
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 * 
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Library General Public License for more details.
 * 
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor Boston, MA 02110-1301,  USA
 */
 
#import "LLWS.h"
#import <sys/socket.h>
#import <netinet/in.h>
#include <arpa/inet.h>

#pragma mark LLWS Private Extension

@interface LLWS ()
-(void)acceptConnection:(NSNotification *)notification;
-(void)receiveIncomingData:(NSNotification *)notification;
-(void)closeConnection:(NSFileHandle *)incomingFileHandle;
-(void)cullConnections:(id)sender;
-(NSData*)fetchReponseForHTTP:(CFHTTPMessageRef)message;
@end

#pragma mark LLWSConnectionInfo Private

@interface LLWSConnectionInfo : NSObject
{
    CFHTTPMessageRef    message;
    NSDate              *createdDate;
    NSNumber            *bytesReceived;
}
@property (assign) CFHTTPMessageRef     message;
@property (strong) NSDate               *createdDate;
@property (strong) NSNumber             *bytesReceived;
@end

@implementation LLWSConnectionInfo
@synthesize message, createdDate, bytesReceived;

- (id)init {
    self = [super init];
    if (self) {
        [self setMessage:CFHTTPMessageCreateEmpty( NULL, TRUE )];
        [self setCreatedDate:[NSDate date]];
        [self setBytesReceived:[NSNumber numberWithLongLong:0]];
    }
    return self;
}

- (void)dealloc {
    CFRelease( message );
}
@end

#pragma mark LLWS Private

@implementation LLWS
{
    CFSocketRef             acceptConnectionsSocket;
    NSFileHandle            *acceptConnectionsFileHandle;
    NSNetService            *bonjourService;
    NSMutableDictionary     *incomingConnections;
    NSTimer                 *cullTimer;
    NSString*               bonjourName;
    int                     maxIncomingMessages;
    int                     maxIncomingTime;
    UInt16                  acceptConnectionsPort;
    unsigned long           maximumMessageSize;
}

@synthesize delegate;

- (id)initWithPort:(UInt16)listenPort
       bonjourName:(NSString*)name
          delegate:(NSObject<LLWSDelegate>*)mydelegate
           timeout:(int)timeout
maximumConnections:(int)maxConnections
maximumMessageSize:(unsigned long)maxHTTPSize
{
    self = [super init];
    if ( self )
    {
        incomingConnections = [NSMutableDictionary dictionary];
        bonjourName = [name copy];
        delegate = mydelegate;
        acceptConnectionsPort = listenPort;
        maxIncomingMessages = maxConnections;
        maxIncomingTime = timeout;
        maximumMessageSize = maxHTTPSize;
    }
    
    return self;
}

-(void)dealloc
{
    [self stop];
}

-(BOOL)start:(NSError**)error
{
    OSStatus    errorCode = noErr;
	int         yes = true;
    
    // Switch to using NSSocketPort when avaliable in iOS.

    // Socket.
	if ( (acceptConnectionsSocket = CFSocketCreate( kCFAllocatorDefault, PF_INET, SOCK_STREAM, IPPROTO_TCP, 0, NULL, NULL )) == NULL )
    {
        if ( error != nil ) {
            *error = [NSError errorWithDomain:NSOSStatusErrorDomain code:-1 userInfo:nil];
        }
#if DEBUG
		NSLog(@"acceptConnectionsSocket == NULL");
#endif
		return NO;
	}
    
    // Socket options & address
	if ( setsockopt( CFSocketGetNative((CFSocketRef)acceptConnectionsSocket), SOL_SOCKET, SO_REUSEADDR, (void *)&yes, sizeof(yes)) != 0 || 
         setsockopt( CFSocketGetNative((CFSocketRef)acceptConnectionsSocket), SOL_SOCKET, SO_NOSIGPIPE, (void *)&yes, sizeof(yes)) != 0 )
    {
        if ( error != nil ) {
            *error = [NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:nil];
        }
#if DEBUG
		NSLog(@"Can't set socket options.");
#endif
        return NO;
	}

	struct sockaddr_in address = {};
	address.sin_len = sizeof(address);
	address.sin_family = AF_INET;
	address.sin_addr.s_addr = htonl(INADDR_ANY);
	address.sin_port = htons(acceptConnectionsPort);
    errorCode = CFSocketSetAddress( acceptConnectionsSocket, (__bridge CFTypeRef)[NSData dataWithBytes:&address length:sizeof(address)] );
	if ( errorCode != kCFSocketSuccess )
    {
        if ( error != nil ) {
            // OSStatus errorCode is usually just -1. Use errno which is correct.
            *error = [NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:nil];
        }
#if DEBUG
		NSLog(@"Unable to bind socket to address. Port is probably already in use.");
#endif
		return NO;
	}

    acceptConnectionsFileHandle = [[NSFileHandle alloc] initWithFileDescriptor:CFSocketGetNative(acceptConnectionsSocket) closeOnDealloc:YES];
    [acceptConnectionsFileHandle acceptConnectionInBackgroundAndNotify];

    // Listen for connection notifications....
	[[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(acceptConnection:)
                                                 name:NSFileHandleConnectionAcceptedNotification
                                               object:nil];

    // Register bonjour service....
    if ( [bonjourName length] ) {
        bonjourService = [[NSNetService alloc] initWithDomain:@"" type:@"_http._tcp." name:bonjourName port:acceptConnectionsPort];
        [bonjourService publish];
    }
    
    return( YES );
}

-(void)stop
{
    // Don't listen for connections...
	[[NSNotificationCenter defaultCenter] removeObserver:self
                                                    name:NSFileHandleConnectionAcceptedNotification
                                                  object:nil];
    
    // Shutdown Bonjour...
    [bonjourService stop];
    bonjourService = nil;

    // Close any existing connections...
	for ( NSFileHandle *incomingFileHandle in [incomingConnections allKeys] ) {
		[self closeConnection:incomingFileHandle];
	}

    // Kill incoming connection file handle and socket...
//    acceptConnectionsFileHandle = nil;
    [acceptConnectionsFileHandle closeFile];

	if ( acceptConnectionsSocket != NULL ) {
		CFSocketInvalidate( acceptConnectionsSocket );
		CFRelease( acceptConnectionsSocket );
		acceptConnectionsSocket = NULL;
	}
}

- (void)acceptConnection:(NSNotification *)notification
{       
    // Grab file handle for new connection..
	NSFileHandle        *incomingFileHandle = [[notification userInfo] objectForKey:NSFileHandleNotificationFileHandleItem];
    
    {
        struct sockaddr_in address = {};
        unsigned int addressSize = sizeof(address);
        
        if (!getsockname( (int)[incomingFileHandle fileDescriptor], (struct sockaddr *)&address, &addressSize)) {
            NSString*   addr = [NSString stringWithFormat: @"%s", inet_ntoa(address.sin_addr)];
            NSLog(@"%@", addr);
        }
    }

    // Create a dictionary to hold info on new connection...
    [incomingConnections setObject:[[LLWSConnectionInfo alloc] init] forKey:incomingFileHandle];

    // Register notification for incoming data...
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(receiveIncomingData:) 
                                                 name:NSFileHandleDataAvailableNotification 
                                               object:incomingFileHandle];

    // Read data..
    [incomingFileHandle waitForDataInBackgroundAndNotify];
    
    // Wait for new connections again..
	[acceptConnectionsFileHandle acceptConnectionInBackgroundAndNotify];
    
    // Clear out any connections that exceed limits...
    [self cullConnections:nil];
    
    // Install timer to monitor for timeouts.
    if ( maxIncomingTime > 1 && [incomingConnections count] == 1 ) {
        cullTimer = [NSTimer scheduledTimerWithTimeInterval:maxIncomingTime/2 target:self selector:@selector(cullConnections:) userInfo:nil repeats:YES];
    }
}

- (void)closeConnection:(NSFileHandle *)incomingFileHandle
{
    // Don't listen for incoming data...
	[[NSNotificationCenter defaultCenter] removeObserver:self 
                                                    name:NSFileHandleDataAvailableNotification 
                                                  object:incomingFileHandle];
    
    // Close and remove info dictionary...
    [incomingFileHandle closeFile];
	[incomingConnections removeObjectForKey:incomingFileHandle];
    
    // Remove timer if there aren't any active connections...
    if ( cullTimer != nil && [incomingConnections count] == 0 ) {
        [cullTimer invalidate];
        cullTimer = nil;
    }
}

-(void)cullConnections:(id)sender
{
    NSMutableArray  *objectToRemove = [NSMutableArray array];
    NSDate          *oldestConnectionDate = nil;
    NSObject        *oldestConnectionKey = nil;
    
    // Loop over all the connections.
   for ( NSObject* key in [incomingConnections allKeys] )
   {
       LLWSConnectionInfo   *info = [incomingConnections objectForKey:key];
       NSDate               *creationDate = [info createdDate];
       
       // If maximum number of connections has been exceeded, close the oldest....
       if ( maxIncomingMessages > 0 && [incomingConnections count] > maxIncomingMessages )
       {
           if ( oldestConnectionKey == nil || [creationDate isLessThan:oldestConnectionDate] ) {
               oldestConnectionKey = key;
               oldestConnectionDate = creationDate;
           }
       }
       
       // Has this connection timed out? If so add it to the close queue...
       if ( maxIncomingTime > 0 && [creationDate isLessThan:[NSDate dateWithTimeIntervalSinceNow:-maxIncomingTime]] ) {
           [objectToRemove addObject:key ];
       }
   }
    
    // Add oldest connection to queue....
    if ( oldestConnectionKey != nil ) {
        [objectToRemove addObject:oldestConnectionKey];
    }

    // Close connections.
    for ( NSFileHandle* connection in objectToRemove ) {
        [self closeConnection:connection];
    }
}

- (void)receiveIncomingData:(NSNotification *)notification
{
	NSFileHandle        *incomingFileHandle = [notification object];
	NSData              *newData = [incomingFileHandle availableData];	
    LLWSConnectionInfo  *info = [incomingConnections objectForKey:incomingFileHandle];
    CFHTTPMessageRef    httpMessage = [info message];

    if ( info == nil ) {
        NSLog( @"receiveIncomingData called for unknown connection. %@", incomingFileHandle );
        return;
    }

    // No new data? Kill it.
    if ( [newData length] == 0 ) {
		[self closeConnection:incomingFileHandle];
        return;
	}
        
    // Add new data to message...
    if ( CFHTTPMessageAppendBytes( httpMessage, [newData bytes], [newData length]) == NO ) {
#if DEBUG
        NSLog(@"CFHTTPMessageAppendBytes failed. Bad data. Kill it.");
#endif
		[self closeConnection:incomingFileHandle];
        return;
    }
        
    // Have we exceeled the max data received limit?
    NSNumber    *bytesReceived = [NSNumber numberWithLong:[[info bytesReceived] unsignedLongValue] + [newData length]];
    [info setBytesReceived:bytesReceived];
    if ( maximumMessageSize > 0 && [bytesReceived unsignedLongValue] > maximumMessageSize ) {
#if DEBUG
        NSLog(@"[bytesReceived unsignedLongValue] > maximumMessageSize. Kill it");
#endif
		[self closeConnection:incomingFileHandle];
        return;
    }

    // Have we got a full message request?
    if ( CFHTTPMessageIsHeaderComplete( httpMessage ) == YES )
    {
        BOOL    sendReply = YES;
        
        // Have we got the entire message, including body?
        long         contentLength = [CFBridgingRelease(CFHTTPMessageCopyHeaderFieldValue( httpMessage, (CFTypeRef)@"Content-Length" )) integerValue];
        if ( contentLength > 0 ) {
            NSData*    content = CFBridgingRelease(CFHTTPMessageCopyBody( httpMessage ));
            if ( content == NULL || contentLength > [content length] ) {
                sendReply = NO;
            }
        }

        // Call delegate to get resonse HTTP....
        if ( sendReply == YES )
        {
            NSData* reply = [self fetchReponseForHTTP:httpMessage];
            
            // Send response...
            if ( [reply length] ) {
                @try { [incomingFileHandle writeData:reply]; } @catch ( NSException *exception ) { /*NSLog(@"LLWS: %@", exception); // Broken pipe is very common.*/ }  
            }

            [self closeConnection:incomingFileHandle];
            return;
        }        
    }
    
    // Keep reading data....
    [incomingFileHandle waitForDataInBackgroundAndNotify];
}

-(NSData*)fetchReponseForHTTP:(CFHTTPMessageRef)message
{
    NSData              *reply = nil;
    NSURL               *requestURL = CFBridgingRelease(CFHTTPMessageCopyRequestURL(message));
    NSMutableDictionary *response = [NSMutableDictionary dictionary];
    
    [delegate replyToHTTPMessage:message requestURL:requestURL reply:response];
    
    // Did we get a block of HTTP?
    reply = [response objectForKey:kZHSResponseHTTPData];
    if ( reply == nil )
    {        
        // Got a status code?
        CFIndex statusCode = [[response objectForKey:kZHSResponseStatusCode] longValue];
        if ( statusCode == 0 ) {
            statusCode = 200; // No code?!?!?
        }

        // Got some body?
        NSData*   body = [response objectForKey:kZHSResponseBody];
        if ( body == nil ) {
            body = [[NSString stringWithFormat:@"<html>%d</html>", (int)statusCode] dataUsingEncoding:NSUTF8StringEncoding];
        }

        // Got a content type?
        NSString*   contentType = [response objectForKey:kZHSResponseContentType];
        if ( contentType == nil ) { 
            contentType = @"text/html";
        }

        // Package into HTTP...
        CFHTTPMessageRef response = CFHTTPMessageCreateResponse( NULL, statusCode, NULL, kCFHTTPVersion1_1);
        if ( response != NULL ) {
            CFHTTPMessageSetHeaderFieldValue( response,  (__bridge CFTypeRef)@"Content-Type", (__bridge CFTypeRef)contentType);
            CFHTTPMessageSetHeaderFieldValue( response, (__bridge CFTypeRef)@"Connection", (__bridge CFTypeRef)@"close");
            CFHTTPMessageSetBody( response, (__bridge CFTypeRef)body);
            
            reply = CFBridgingRelease(CFHTTPMessageCopySerializedMessage(response));
            
            CFRelease(response);
        }
    }
        
    return( reply );
}

@end
