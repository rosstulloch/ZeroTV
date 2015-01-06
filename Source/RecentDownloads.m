//
//  RecentDownloads.m
//  TVJunkie
//
//  Created by Ross Tulloch on 14/01/11.
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
 
#import "RecentDownloads.h"
#import "PrefsKeys.h"
#import "TVJunkieAppDelegate.h"

static  RecentDownloads *sharedInstance = nil;

@implementation RecentDownloads
{
    IBOutlet    NSMenuItem      *	recentDownloadsSubMenuItem; // File -> Downloads.
    FSEventStreamRef	fsEventStreamRef;
}

@synthesize recentDownloads;

+(RecentDownloads*)sharedInstance {
    if ( sharedInstance == nil ) {
        NSLog(@"sharedInstance == nil. RecentDownloads is loaded from nib.");
    }
    
    return( sharedInstance );
}

-(void)awakeFromNib 
{    
	[super awakeFromNib];

    sharedInstance = self;
       
    [self setRecentDownloads:[[NSMenu alloc] initWithTitle:@"Not important."]];

    if ( PreferenceForKey( kPrefDownloadsFolder ) == nil ) {
        NSData* dldsFolder = [NSKeyedArchiver archivedDataWithRootObject:[NSURL fileURLWithPath:[@"~/Downloads/" stringByExpandingTildeInPath]]];
		[[NSUserDefaults standardUserDefaults] setObject:dldsFolder forKey:kPrefDownloadsFolder];
	}

	[[NSDistributedNotificationCenter defaultCenter] addObserver:self
                                                        selector:@selector(downloadFileFinished:)
                                                            name:@"com.apple.DownloadFileFinished"
                                                          object:nil
                                              suspensionBehavior:NSNotificationSuspensionBehaviorDeliverImmediately];

	[self startWatchingDownloadsFolder];	
	[self buildRecentDownloadsMenuInThread];
}

#pragma mark scanForVideoFiles

-(NSURL*)downloadsFolder {
    return( [NSKeyedUnarchiver unarchiveObjectWithData:PreferenceForKey( kPrefDownloadsFolder )] );
}

-(BOOL)hasVideoFileTypeExtension:(NSString*)fileName
{
    NSArray*    videoExtensions = [PreferenceForKey(@"videoExtensions") componentsSeparatedByString:@","];    
    return [videoExtensions containsObject:[[fileName pathExtension] lowercaseString]];
}

-(BOOL)isVideoSmallerThanMinimunSize:(long long)size
{
	NSNumber*	minFileSizeTag = PreferenceForKey( kPrefFileSizeExclusionTag );
	long long	minFileSize = [minFileSizeTag longLongValue] * (1000 * 1000); // 1MB (Apple Style!)

	return( size < minFileSize );
}

-(BOOL)doesFilePassExclusions:(NSString*)path
{
	BOOL			result = YES;
	NSURL*			theURL = [NSURL fileURLWithPath:path isDirectory:NO];
	NSDictionary*	resourceValues = [theURL resourceValuesForKeys:[NSArray arrayWithObjects:NSURLNameKey, NSURLFileSizeKey, nil] error:nil];

	if ( [self hasVideoFileTypeExtension:[path lastPathComponent]] == NO ||
		 [self isVideoSmallerThanMinimunSize:[[resourceValues objectForKey:NSURLFileSizeKey] longLongValue]] == YES )
    {
		result = NO;
	}				
	
	return( result );
}

-(NSArray*)scanForVideoFiles:(NSURL *)directoryToScan applyExclusions:(BOOL)filterResults
{
    NSMutableArray*			result = [NSMutableArray array];
    NSMutableArray*			interestingItems = [NSMutableArray array];
	NSArray*				propertiesOfInterest = [NSArray arrayWithObjects:NSURLNameKey, NSURLIsDirectoryKey, NSURLContentModificationDateKey, NSURLFileSizeKey, nil];
    NSDate*					recentPast = [[NSDate date] dateByAddingTimeInterval:-(60*60*24*14)]; // 14 days.
    
	NSDirectoryEnumerator*	dirEnumerator = [[NSFileManager defaultManager] enumeratorAtURL:directoryToScan
                                                  includingPropertiesForKeys:propertiesOfInterest
                                                                     options:NSDirectoryEnumerationSkipsHiddenFiles|NSDirectoryEnumerationSkipsPackageDescendants
                                                                errorHandler:nil];
	
    for ( NSURL *theURL in dirEnumerator )
	{
		NSDictionary*	resourceValues = [theURL resourceValuesForKeys:propertiesOfInterest error:nil];
				
		if ( [[resourceValues objectForKey:NSURLIsDirectoryKey] boolValue] == NO &&
			 [self hasVideoFileTypeExtension:[resourceValues objectForKey:NSURLNameKey]] == YES &&
			 [(NSDate*)[resourceValues objectForKey:NSURLContentModificationDateKey] compare:recentPast] == NSOrderedDescending )
		{
			BOOL	shouldAdd = YES;
			
			if ( filterResults == YES )
			{
				if ( [self isVideoSmallerThanMinimunSize:[[resourceValues objectForKey:NSURLFileSizeKey] longLongValue]] == YES ) {
					shouldAdd = NO;					
				}				
			}
			
			if ( shouldAdd == YES ) {
				[interestingItems addObject:[NSDictionary dictionaryWithObjectsAndKeys:	theURL, @"url",
																						[resourceValues objectForKey:NSURLContentAccessDateKey], @"date",
																						[resourceValues objectForKey:NSURLNameKey], @"name",
																						nil]];
			}
		}
     }
	 
	// Sort by Date
	NSSortDescriptor*	sortDesc = [[NSSortDescriptor alloc] initWithKey:@"date" ascending:NO selector:@selector(compare:)];
	[interestingItems sortUsingDescriptors:[NSArray arrayWithObjects:sortDesc, nil]];

	// Remove more than 30....
	const NSUInteger	maxItems = 30;
	if ( [interestingItems count] > maxItems ) {
		[interestingItems removeObjectsInRange:NSMakeRange( maxItems, ([interestingItems count] - maxItems)-1 )];
	}

	// Sort by Name
//	sortDesc = [[[NSSortDescriptor alloc] initWithKey:@"name" ascending:YES selector:@selector(localizedCaseInsensitiveCompare:)] autorelease];
//	[interestingItems sortUsingDescriptors:[NSArray arrayWithObjects:sortDesc, nil]];
	
	// Copy to results array...
	for ( NSDictionary* item in interestingItems ) {
		[result addObject:[item objectForKey:@"url"]];
	}
 	
	return( result );
}

#pragma mark Recent Download Menu

-(void)buildRecentDownloadsMenuInThread {
	[NSThread detachNewThreadSelector:@selector(buildRecentDownloadsMenuThreadEntry:) toTarget:self withObject:nil];
}

-(void)buildRecentDownloadsMenuThreadEntry:(id)arg
{
	@autoreleasepool {

#if DEBUG
        NSLog(@"buildRecentDownloadsMenuThreadEntry" );
#endif
        
	NSArray*	recentFiles = [self scanForVideoFiles:[self downloadsFolder] applyExclusions:NO];
        if ( [recentFiles count] ) {
            [self performSelectorOnMainThread:@selector(buildRecentDownloadsMenuWithItems:) withObject:recentFiles waitUntilDone:NO];
        }

#if DEBUG
        NSLog(@"buildRecentDownloadsMenuThreadEntry done." );
#endif

	}
}

-(void)buildRecentDownloadsMenuWithItems:(NSArray*)urls
{
    [recentDownloads removeAllItems];

	for ( NSURL *theURL in urls )
	{
		NSString*	fileName = [[[theURL path] lastPathComponent] stringByDeletingPathExtension];
				
		NSMenuItem*	menuItem = [[NSMenuItem alloc] initWithTitle:fileName action:@selector(recentDownloadAction:) keyEquivalent:@""];
		[menuItem setRepresentedObject:theURL];
		[recentDownloads addItem:menuItem];		
	}
	
    // Add to File -> Downloads.
	[recentDownloadsSubMenuItem setSubmenu:recentDownloads];
}

-(void)startWatchingDownloadsFolder
{	
	if ( fsEventStreamRef != NULL ) {
		FSEventStreamStop( fsEventStreamRef );
		FSEventStreamInvalidate( fsEventStreamRef );
		FSEventStreamRelease( fsEventStreamRef );
		fsEventStreamRef = NULL;
	}

	// Start watching for file events....
	fsEventStreamRef = FSEventStreamCreate(	NULL,
											RecentDownloadsFSEventStreamCallback,
											NULL,
											(__bridge CFArrayRef)[NSArray arrayWithObject:[[self downloadsFolder] path]],
											kFSEventStreamEventIdSinceNow,
											15,
											kFSEventStreamCreateFlagUseCFTypes );
	if ( fsEventStreamRef != NULL ) {
		FSEventStreamScheduleWithRunLoop( fsEventStreamRef, CFRunLoopGetCurrent(), kCFRunLoopDefaultMode );
		FSEventStreamStart( fsEventStreamRef );
	}
}

void	RecentDownloadsFSEventStreamCallback( ConstFSEventStreamRef	streamRef,
									void					*clientCallBackInfo,
									size_t					numEvents,
									void					*eventPaths,
									const					FSEventStreamEventFlags eventFlags[],
									const					FSEventStreamEventId eventIds[])
{
	[[RecentDownloads sharedInstance] buildRecentDownloadsMenuInThread];
}

#pragma mark DownloadFileFinished Notification

-(void)downloadFileFinished:(NSNotification*)notification
{
#if DEBUG
	NSLog(@"downloadFileFinished: %@", notification);
#endif

	if ( PreferenceBoolForKey( kPrefAutoQueueVideoFromDownloads ) == NO ) {
		return;
	}
	
	if ( [notification object] != nil )
	{
		NSString*	filePath = [notification object];
		BOOL		isDirectory = NO;
		
		// Folder or File?
		if ( [[NSFileManager defaultManager] fileExistsAtPath:filePath isDirectory:&isDirectory] == YES )
		{
			if ( isDirectory == NO )
			{
				// Queue it
				if ( [self doesFilePassExclusions:[notification object]] == YES ) {
					[((TVJunkieAppDelegate*)[NSApp delegate]) application:NSApp openFile:[notification object]];
				}
			} else
			{
				NSURL*	folderURL = [NSURL fileURLWithPath:filePath isDirectory:YES];
				
				// Make sure the folder isn't the downloads folder.
				if ( [[self downloadsFolder] isEqual:folderURL] == NO )
				{
					// List all of the video in the folder...
					NSArray*	videoFiles = [self scanForVideoFiles:folderURL applyExclusions:YES];
					
					// ...and queue 'em...
					for ( NSURL* file in videoFiles ) {
						[((TVJunkieAppDelegate*)[NSApp delegate]) application:NSApp openFile:[file path]];
					}
				}
			}
		}
	} else {
		NSLog(@"DownloadFileFinished notification sent with object equal to nil.");
	}
}

@end
