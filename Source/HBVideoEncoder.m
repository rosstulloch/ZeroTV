//
//  Encoder.m
//  TVJunkie
//
//  Created by Ross Tulloch on 12/01/11.
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
 
#import "HBVideoEncoder.h"
#import "PrefsKeys.h" 
#import "ResourcesSupport.h"

@interface HBVideoEncoder ()
@property (unsafe_unretained)	id<HBVideoEncoderDelegate>		delegate;
@property (strong)	NSTask*							hbTask;
@property (strong)	NSURL*							exportedMovie;
@property (assign)	time_t                          lastProgressUpdate;
@end

static  HBVideoEncoder *sharedInstance = nil;

@implementation HBVideoEncoder
{
    IBOutlet	NSArrayController*			queueController;
    BOOL                                    shownInitialProgressEstimatingMsg;
}

@synthesize hbTask = _hbTask, exportedMovie = _exportedMovie, userCanceled = _userCanceled, delegate = _delegate, originalMovie = _originalMovie, lastProgressUpdate = _lastProgressUpdate, lastProgressPercentage = _lastProgressPercentage;

+(HBVideoEncoder*)sharedInstance {
    if ( sharedInstance == nil ) {
        NSLog(@"sharedInstance == nil. HBVideoEncoder is loaded from nib.");
    }
    
    return( sharedInstance );
}

-(void)awakeFromNib
{
    sharedInstance = self;
    
//    NSLog( @"%@", [self cleanupName:@"Witness.1985.720p.HDTV.x264.YIFY"]);
    
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(queueFileRequest:) name:kNotifyQueueFileRequest object:nil];
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(hbTerminated:) name:NSTaskDidTerminateNotification object:nil];	

	[self alertIfHBCannotBeFound];
}

-(BOOL)isBusy {
	return( _hbTask != nil || [[queueController content] count] );
}

-(BOOL)askIfIsOKToQuit {
	return( [_delegate askIfIsOKToQuit] );
}

#pragma mark Queue

-(void)addToQueue:(NSString*)fullPath
{
	[queueController addObject:[NSURL fileURLWithPath:fullPath]];
	[self convertNextFileInQueue];
	[_delegate didQueueFile];
}

-(void)queueFileRequest:(NSNotification *)aNotification
{
	[queueController addObject:[aNotification object]];
	[self convertNextFileInQueue];
	[_delegate didQueueFile];	
}

-(NSArray*)displayNamesOfItemsInQueue
{
    NSMutableArray* result = [NSMutableArray array];
    
    for ( NSString* item in [queueController arrangedObjects] ) {
        [result addObject:[item lastPathComponent]];
    }
    
    return( result );
}

-(void)convertNextFileInQueue
{
//    return;
    
	if ( _hbTask != nil || [[queueController arrangedObjects] count] == 0 ) {
		return;
	}
	
	NSURL*	fileURL = [[queueController arrangedObjects] objectAtIndex:0];
	[queueController removeObject:fileURL];
	[self convert:[fileURL path]];
}

#pragma mark Handbreak

-(void)alertIfHBCannotBeFound
{    
	if ( [self pathToHandbreakCLI] == nil ) {
		NSAlert* alert = [NSAlert alertWithMessageText:@"You'll need to download the Handbreak command line interface."
                                         defaultButton:@"Visit Handbreak downloads page"
                                       alternateButton:nil
                                           otherButton:@"Just Quit"
                             informativeTextWithFormat:@"Please visit the Handbreak downloads page and click the download link. \nAfter downloading, open the disk image and drag \"HandbreakCLI\" to the Applications folder."];
        
		if ( [alert runModal] == NSAlertDefaultReturn ) {
			[[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"http://handbrake.fr/downloads2.php"]];
		}
		[NSApp terminate:nil];
	}
}

-(NSString*)pathToHandbreakCLI
{
    NSString*   result = nil;
    NSArray*    possibleLocations = [NSArray arrayWithObjects:@"/Applications/HandBrakeCLI",
                                     [@"~/Applications/HandBrakeCLI" stringByExpandingTildeInPath],
                                     @"/usr/bin/HandBrakeCLI",
                                     @"/Applications (Other)/HandBrakeCLI",
                                     nil];
    
    for ( NSString* path in possibleLocations )
    {
        if ( [[NSFileManager defaultManager] fileExistsAtPath:path] == YES ) {
            result = path;
            break;
        }
    }
    
    return( result );
}

-(void)cancel
{
	if ( _hbTask != nil ) {
		[_hbTask terminate];
	}
}

-(void)hbReadNotify:(NSNotification*)notification
{
	// Pull data from HB...
	NSData*		data = [[notification userInfo] objectForKey:NSFileHandleNotificationDataItem];	
	if ( data != nil ) {
		// Use hb data to update progress...
		[self processProgressStringFromHB:[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]];
	}
	
	if ( _hbTask != nil ) {
		[[notification object] readInBackgroundAndNotify];	
	} else {
		[_delegate finishedProgress];
	}
}

-(BOOL)moveToTrash:(NSURL*)url
{
	FSRef	newMovieRef = {};
	CFURLGetFSRef( (__bridge CFURLRef)url, &newMovieRef );
	OSStatus error = FSMoveObjectToTrashSync( &newMovieRef, NULL, kFSFileOperationDefaultOptions );
	// Using Core File Manager so we can do the move synchronously.
	
	return( error == noErr  );
}

- (void)hbTerminated:(NSNotification *)aNotification
{
	NSError*	error = nil;

	[self setHbTask:nil];    
	[[NSNotificationCenter defaultCenter] removeObserver:self name:NSFileHandleReadCompletionNotification object:nil];
	
	if ( _userCanceled == YES )
	{
		// Movie partial file to trash
		if ( [_exportedMovie checkResourceIsReachableAndReturnError:&error] == YES ) {
			[self moveToTrash:_exportedMovie];
		}
		
		[_delegate setProgressText:@""];		
	} else
	if ( [_exportedMovie checkResourceIsReachableAndReturnError:&error] == YES )
	{
		// Remove .converting from name
		NSURL*		renamedMovie = [_exportedMovie URLByDeletingPathExtension];
		
		// Does item with new name already exists? Move it to trash.
		if ( [renamedMovie checkResourceIsReachableAndReturnError:&error] == YES ) {
			[self moveToTrash:_exportedMovie];
		}
		
		// Rename
		if ( [[NSFileManager defaultManager] moveItemAtURL:_exportedMovie toURL:renamedMovie error:&error] == YES ) {
			[self setExportedMovie:renamedMovie];
		}
		
		[_delegate setProgressText:@"Export finished."];
		
		// Open in iTunes
		if ( PreferenceBoolForKey( kPrefAddToTunes ) == YES ) {
			[self addToTunes:_exportedMovie];
			
			// Move to trash
			if ( PreferenceBoolForKey( kPrefTrashAfterAddingToTunes ) == YES ) {
				[self moveToTrash:_exportedMovie];
			}
		}
		
		if ( PreferenceBoolForKey( kPrefTrashOriginalMovie) == YES ) {
			[self moveToTrash:_originalMovie];
		}
		
	} else {
		[[NSAlert alertWithMessageText:@"Sorry, an error occured."
                         defaultButton:@"OK"
                       alternateButton:nil
                           otherButton:nil
             informativeTextWithFormat:@"The movie couldn't be exported. Open Console.app (inside Applications/Utilities) for error details."]
         runModal];
	}

    [self setLastProgressPercentage:0];    
    [self setOriginalMovie:nil];
    [self setExportedMovie:nil];

	[_delegate finishedProgress];
	[self convertNextFileInQueue];
}

-(void)convert:(NSString *)filePath
{
    NSPipe			*stdOut = [NSPipe pipe];
    NSFileHandle	*outputFile = [stdOut fileHandleForReading];
	NSString*		hbPath = [self pathToHandbreakCLI];
	NSMutableArray*	args = [NSMutableArray array];
	NSArray*		defaultArgs = [PreferenceForKey(kPrefHBArgs) componentsSeparatedByString:@" "];

	[_delegate startProgress];
	[_delegate setSummaryText:filePath];
    [_delegate setProgressText:@"Starting. This may take a few moments."];

    shownInitialProgressEstimatingMsg = NO;
    
    NSString    *fileName = [filePath lastPathComponent];

    // If path is to root of disk, assume it's a DVD and make that work.
    NSNumber *isVolume = nil;
    if ( [[NSURL fileURLWithPath:filePath] getResourceValue:&isVolume forKey:NSURLIsVolumeKey error:nil] && [isVolume boolValue] ) {
        filePath = [filePath stringByAppendingPathComponent:@"VIDEO_TS"];
    }
    
	[self setOriginalMovie:[NSURL fileURLWithPath:filePath]];
	[self setHbTask:[[NSTask alloc] init]];
		
	// Input
	[args addObject:@"-i"];
	[args addObject:filePath];
	
	// Output into ~/Movies. Source maybe read-only.
	[args addObject:@"-o"];
    
    NSString	*newMoviePath = [/*[@"~/Movies/" stringByExpandingTildeInPath]*/NSTemporaryDirectory() stringByAppendingPathComponent:[self cleanupName:fileName]];
	newMoviePath = [[newMoviePath stringByDeletingPathExtension] stringByAppendingPathExtension:@"m4v"];
	newMoviePath = [newMoviePath stringByAppendingPathExtension:@"exporting"];
	[self setExportedMovie:[NSURL fileURLWithPath:newMoviePath]];    
	[args addObject:[_exportedMovie path]];
	
	// Preset
	NSString*	presetTitle = [PreferenceForKey(@"tagIDToPresetDictionary") objectForKey:[PreferenceForKey(kPresetTagID) stringValue]];
	[args addObject:[NSString stringWithFormat:@"--preset=%@", presetTitle]];

	// Final args...
	[args addObjectsFromArray:defaultArgs];
	
	// Task
	[_hbTask setLaunchPath:hbPath];
	[_hbTask setArguments:args];
	[_hbTask setStandardOutput:stdOut];

	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(hbReadNotify:) name:NSFileHandleReadCompletionNotification object:outputFile ];

	@try {
		[_hbTask launch];
	} @catch (NSException * e) {
		NSAlert* alert = [NSAlert alertWithError:[NSError errorWithDomain:[e reason] code:-1 userInfo:nil]];
		[alert beginSheetModalForWindow:[NSApp mainWindow] modalDelegate:self didEndSelector:nil contextInfo:nil];
	}
	
	if ( _hbTask != nil ) {
		[outputFile readInBackgroundAndNotify];
	}

	[_delegate didPerformUIAction:nil];
}

#pragma mark iTunes

-(NSString*)cleanupName:(NSString*)name
{
    NSString*       result = [name stringByDeletingPathExtension];

    NSRange   episodeRange = [name rangeOfString:@"S[0-9]{2}E[0-9]{2}" options:NSRegularExpressionSearch|NSCaseInsensitiveSearch];
    if ( episodeRange.location != NSNotFound ) {
        result = [result substringToIndex:episodeRange.location+episodeRange.length];
    }
    
    NSRange   yearRange = [result rangeOfString:@"19[0-9]{2}|20[0-9]{2}" options:NSRegularExpressionSearch|NSCaseInsensitiveSearch];
    if ( yearRange.location != NSNotFound ) {
        result = [result stringByReplacingCharactersInRange:yearRange withString:@""];
    }
    
    // Remove known strings...
    NSArray *cleanStrings = [[ResourcesSupport dictionaryWithName:@"CleanStrings.plist"] objectForKey:@"cleanStrings"];
    for ( NSString* str in cleanStrings ) {
        result = [result stringByReplacingOccurrencesOfString:str withString:@"" options:NSCaseInsensitiveSearch range:NSMakeRange(0, [result length])];
    }
    
    // Remove punctuation...
    NSUInteger  characterIndex = 0;
    while ( characterIndex < [result length] ) {
        unichar character = [result characterAtIndex:characterIndex];
        if ( [[NSCharacterSet punctuationCharacterSet] characterIsMember:character] ) {
            result = [result stringByReplacingOccurrencesOfString:[NSString stringWithCharacters:&character length:1] withString:@" "];
            characterIndex = 0;
        } else {
            ++characterIndex;
        }
    }
    
    // We've possibly got lots of double spaces now. Let's remove them.
    while ( [result rangeOfString:@"  "].location != NSNotFound ) {
        result = [result stringByReplacingOccurrencesOfString:@"  " withString:@" "];
    }
    
    return result;
}

-(void)addToTunes:(NSURL*)file
{
    NSString*		finalScript = [NSString stringWithFormat:PreferenceForKey(kPrefAddToiTunesScript), [file path]];
	NSAppleScript*	aeRunner = [[NSAppleScript alloc] initWithSource:finalScript];
	if ( aeRunner != nil ) {
		NSDictionary*			errorInfo = nil;
		
		[_delegate setProgressText:@"Adding to iTunes..."];
		
		NSAppleEventDescriptor* result = [aeRunner executeAndReturnError:&errorInfo];
        if ( errorInfo != nil ) {
            NSLog(@"addToTunes failed: %@ %@", result, errorInfo );
        }
	}
	
	[_delegate setProgressText:@"Movie has been added to iTunes."];
}

#pragma mark Handbreak progress string reformatter. Fantastically Fugly.

-(void)processProgressStringFromHB:(NSString*)text
{	
	// Is this a "Encoding" progress string from hb? 
	if ( [text rangeOfString:@"Encoding"].location == NSNotFound ) {
		return;			
	}
    
	// Update once per second
	if ( time(NULL) == _lastProgressUpdate ) {
		return;
	}
	[self setLastProgressUpdate:time(NULL)];
    
	NSString*	progressText = @"";
	
	// Option key down? Show original string....
	if ( [[NSApp currentEvent] modifierFlags] & NSAlternateKeyMask ) {
		[_delegate setProgressText:[text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]];	
		return;
	}
    
	// Remove unwanted junk...
	for ( NSString* stringToDelete in [NSArray arrayWithObjects:@"fps", @"avg", @"ETA", @"(", @")", @" ", @"\n", nil] ) {
		text = [text stringByReplacingOccurrencesOfString:stringToDelete withString:@""];
	}
	
	// Split...
	NSArray*	elements = [text componentsSeparatedByCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"%,"]];
    
	// Percentage.
	if ( [elements count] >= 2 ) {
		double	percentageComplete = [[elements objectAtIndex:1] doubleValue];
        [self setLastProgressPercentage:percentageComplete];
        [_delegate setProgressDoubleValue:_lastProgressPercentage];
		progressText = [progressText stringByAppendingFormat:@"%.1f%%", percentageComplete];
		
		// Dock.
		NSString* dockText = [NSString stringWithFormat:@"%.0f%%", percentageComplete];
		[[[NSApplication sharedApplication] dockTile] setBadgeLabel:dockText];
	}
	
	// FPS. Time.
	if ( [elements count] >= 5 )
	{
		NSString*	fps = [elements objectAtIndex:3];
		NSString*	timeRemaining = [elements objectAtIndex:4];
		NSArray*	timeElements = [timeRemaining componentsSeparatedByCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"hms"]];
		
		timeRemaining = @"About ";
		
		// Time
		if ( [timeElements count] >= 3 )
		{
			int	hours = [[timeElements objectAtIndex:0] intValue];
			int	minutes = [[timeElements objectAtIndex:1] intValue];
            
			if ( hours != 0 ) {
				timeRemaining = [timeRemaining stringByAppendingFormat:@"%d hour and ", hours];
			}
			if ( minutes != 0 || hours != 0 ) {
				timeRemaining = [timeRemaining stringByAppendingFormat:minutes > 1 ? @"%d minutes" : @"%d minute", minutes];
			} else {
				if ( hours == 0 ) {
					timeRemaining = @"Less than a minute";
				}
			}
		}
		progressText = [progressText stringByAppendingFormat:@" - %@ (%.0f fps)", timeRemaining, [fps doubleValue]];
        shownInitialProgressEstimatingMsg = YES;
	} else {
        if ( shownInitialProgressEstimatingMsg == YES ) {
            return;
        }
        progressText = [progressText stringByAppendingString:@" - Estimating time remaining..."];
	}
	
	[_delegate setProgressText:progressText];	
}


@end
