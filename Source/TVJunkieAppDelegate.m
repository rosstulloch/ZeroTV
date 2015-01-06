//
//  TVJunkieAppDelegate.m
//  TVJunkie
//
//  Copyright 2011 Ross Tulloch. All rights reserved.
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
 
#import "TVJunkieAppDelegate.h"
#import "PrefsKeys.h"
#import "HBVideoEncoder.h"
#import "RecentDownloads.h"
#import "LLWS.h"
#import "ResourcesSupport.h"

@implementation TVJunkieAppDelegate
{	
    LLWS* httpServer;
}

-(void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
#if DEBUG
	[[NSApp dockTile] setBadgeLabel:@"DEBUG"];	
#endif
    
    if ( PreferenceBoolForKey(kWebSeverSupport) ) {
        [self startHTTPServer];
    }
}

-(NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)sender
{
	NSApplicationTerminateReply	result = NSTerminateNow;
	
	if ( [[HBVideoEncoder sharedInstance] isBusy] ) {
		if ( [[HBVideoEncoder sharedInstance] askIfIsOKToQuit] == NO ) {
			result = NSTerminateCancel;
		}
	}
		
	return( result );
}

-(void)applicationWillTerminate:(NSNotification *)notification
{
	[[NSNotificationCenter defaultCenter] postNotificationName:kObjectsShouldSavePrefsNotification object:nil];
	[[NSUserDefaults standardUserDefaults] synchronize];	
}

-(BOOL)application:(NSApplication *)theApplication openFile:(NSString *)filePath
{
	[[HBVideoEncoder sharedInstance] addToQueue:filePath];	
	
	return( YES );
}

-(NSMenu *)applicationDockMenu:(NSApplication *)sender
{    
    NSMenu*	copy = [[[RecentDownloads sharedInstance] recentDownloads] copy];
	[copy insertItem:[[NSMenuItem alloc] initWithTitle:@"Downloads" action:nil keyEquivalent:@""] atIndex:0];
    [copy insertItem:[NSMenuItem separatorItem] atIndex:[copy numberOfItems]];
	[copy insertItem:[[NSMenuItem alloc] initWithTitle:@"Choose..." action:@selector(openDoc:) keyEquivalent:@""] atIndex:[copy numberOfItems]];

	return( copy );
}

-(void)recentDownloadAction:(id)sender
{
	[NSApp activateIgnoringOtherApps:NO];
	[self application:NSApp openFile:[[(NSMenuItem*)sender representedObject] path]];
}

-(IBAction)openDoc:(id)sender
{
    NSOpenPanel *panel = [NSOpenPanel openPanel];
 
 	[[NSNotificationCenter defaultCenter] postNotificationName:kObjectsShouldSavePrefsNotification object:nil];	

    [panel setCanChooseDirectories:YES];
    [panel setAllowsMultipleSelection:YES];
    if ( [panel runModal] == NSOKButton ) {
		for ( NSURL* file in [panel URLs] ) {
			[self application:NSApp openFile:[file path]];
        }
    }
}

#pragma mark webserver

-(void)toggleWebServer:(id)sender
{
    if ( PreferenceBoolForKey(kWebSeverSupport) ) {
        [self startHTTPServer];
    } else {
        [httpServer stop];
        httpServer = nil;
    }
}

-(void)startHTTPServer
{
    httpServer = [[LLWS alloc] initWithPort:PreferenceIntegerForKey(kWebServerPort)
                                          bonjourName:@"ZeroTV"
                                             delegate:self
                                              timeout:60
                                   maximumConnections:4
                                   maximumMessageSize:512];
    
    NSError*    error = nil;
    if ( [httpServer start:&error] == NO ) {
        [NSApp presentError:error];
    }
}

-(NSData*)contentsFromFileInBundle:(NSString*)fileName
{
    NSData    *result = nil;
    
    if ( [fileName length] == 0 || [fileName isEqualToString:@"/"] ) {
        fileName = @"index.html";
    }
    
    NSString    *itemPath = [[NSBundle mainBundle] pathForResource:fileName ofType:nil];
    if ( itemPath != nil ) {
        NSURL   *itemURL = [NSURL fileURLWithPath:itemPath isDirectory:NO];
        result = [NSData dataWithContentsOfURL:itemURL];
    }
    
    return result;
}

-(NSString*)mimeTypeForFileName:(NSString*)fileName
{
    NSDictionary    *extToMimeType = [NSDictionary dictionaryWithObjectsAndKeys: @"text/html", @"html", @"text/css", @"css", nil];
    NSString        *type = [extToMimeType objectForKey:[[fileName pathExtension] lowercaseString]];
    if ( type == nil ) {
        type = @"text/html";
    }
    
    return( type );
}

-(NSString*)replacePlaceholder:(NSString*)tag inBody:(NSString*)body withItems:(NSArray*)items argsFromKeyPaths:(NSArray*)keyPaths
{
    NSString*   result = body;
    NSString*   endTag = @"REPLACE_END";

    if ( keyPaths == nil ) {
        keyPaths = [NSArray arrayWithObject:@"self"];
    }

    NSRange     activeLoc = [body rangeOfString:tag];
    if ( activeLoc.location != NSNotFound )
    {
        NSRange     activeEnd = [body rangeOfString:endTag options:0 range:NSMakeRange(activeLoc.location, [body length] - activeLoc.location)];
        if ( activeEnd.location != NSNotFound )
        {
            NSString*   startBody = [body substringToIndex:activeLoc.location];
            NSString*   endBody = [body substringFromIndex:activeEnd.location + [endTag length]];
            NSString*   tagLine = [body substringWithRange:NSMakeRange(activeLoc.location + [tag length], activeEnd.location - (activeLoc.location+[tag length]))];            
            NSString*   newChunk = @"";

            for ( NSObject* item in items )
            {
                NSString*   newLine = [NSString stringWithString:tagLine];
                
                for ( NSString* keyPath in keyPaths ) {
                    NSRange     activeLoc = [newLine rangeOfString:@"ARG"];
                    if ( activeLoc.location != NSNotFound ) {
                        newLine = [newLine stringByReplacingCharactersInRange:activeLoc withString:[item valueForKeyPath:keyPath]];
                    }
                }
                
                newChunk = [newChunk stringByAppendingString:newLine];
            }
            
            result = [startBody stringByAppendingFormat:@"%@%@", newChunk, endBody];
        }
    }
    
    return( result );
}

-(NSString*)currentMovieName
{
    NSString*   result = [[[[HBVideoEncoder sharedInstance] originalMovie] path] lastPathComponent];
    if ( result == nil ) {
        result = @"ZeroTV is Idle.";
    }
    
    return( result );
}

-(NSString*)currentPercentage
{
    NSString*   result = @"";
    
    if ( [[HBVideoEncoder sharedInstance] lastProgressPercentage] ) { 
        result = [NSString stringWithFormat:@"%g%%", [[HBVideoEncoder sharedInstance] lastProgressPercentage]];
    }
    
    return( result );
}

-(void)replyToHTTPMessage:(CFHTTPMessageRef)message requestURL:(NSURL*)url reply:(NSMutableDictionary*)response
{    
    NSString    *lastFileName = [[url path] lastPathComponent]; 
    NSString    *type = [self mimeTypeForFileName:lastFileName];
    NSString    *body = [[NSString alloc] initWithData:[self contentsFromFileInBundle:lastFileName] encoding:NSUTF8StringEncoding];
    
    body = [self replacePlaceholder:@"REPLACE_ACTIVE_XFER"
                             inBody:body
                          withItems:[NSArray arrayWithObject:self]
                  argsFromKeyPaths:[NSArray arrayWithObjects:@"self.currentMovieName", @"self.currentPercentage", nil]];

    body = [self replacePlaceholder:@"REPLACE_WAITING_XFER"
                             inBody:body
                          withItems:[[HBVideoEncoder sharedInstance] displayNamesOfItemsInQueue]
                  argsFromKeyPaths:nil];

    if ( body == nil ) {
        [response setObject:[NSNumber numberWithLong:404] forKey:kZHSResponseStatusCode];
    } else {
        [response setObject:[NSNumber numberWithLong:200] forKey:kZHSResponseStatusCode];
        [response setObject:type forKey:kZHSResponseContentType];
        [response setObject:[body dataUsingEncoding:NSUTF8StringEncoding] forKey:kZHSResponseBody];
    }
}

@end
