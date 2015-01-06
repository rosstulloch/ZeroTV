//
//  ZeroHTTPServer.h
//  TVJunkie
//
//  Created by Ross Tulloch on 5/08/11.
//  Copyright 2011 Ross Tulloch. All rights reserved.
//
//
//  delegate needs to implement:
//
//      -(void)replyToHTTPMessage:(CFHTTPMessageRef)message requestURL:(NSURL*)url reply:(NSMutableDictionary*)response;
//
//      response dictionary needs to be filled with:
//
//      kZHSResponseStatusCode      NSNumber        HTTP Error Code. For example: 202.
//      kZHSResponseBody            NSData          HTML encode as UTF8. For example: [@"<html>Foobar</html>" dataUsingEncoding:NSUTF8StringEncoding]
//      kZHSResponseContentType     NSString        MIME Content type string. For example: text/html
//             * or *
//      kZHSResponseHTTPData        NSData          Raw block of HTTP to send back to client. Optional.
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
 
#import <Foundation/Foundation.h>

@protocol LLWSDelegate <NSObject>
-(void)replyToHTTPMessage:(CFHTTPMessageRef)message requestURL:(NSURL*)url reply:(NSMutableDictionary*)response;
@end

@interface LLWS : NSObject
@property (unsafe_unretained) NSObject<LLWSDelegate> *delegate;

-(id)initWithPort:(UInt16)listenPort
      bonjourName:(NSString*)name
         delegate:(NSObject*)mydelegate
          timeout:(int)timeout
maximumConnections:(int)maxConnections
maximumMessageSize:(unsigned long)size;

-(BOOL)start:(NSError**)error;
-(void)stop;

@end

#define kZHSResponseStatusCode      @"statusCode"
#define kZHSResponseBody            @"body"
#define kZHSResponseContentType     @"contentType"
#define kZHSResponseHTTPData        @"HTTPData"
