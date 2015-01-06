//
//  EncodeController.m
//  TVJunkie
//
//  Created by Ross Tulloch on 1/01/11.
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
 
#import "EncodeWindowController.h"
#import "HBVideoEncoder.h"
#import "PrefsKeys.h"

@implementation EncodeWindowController
{
    IBOutlet	NSMenuItem*				toggleMainWindowMenuItem;
    IBOutlet	NSTextField*			progressTextField;
    IBOutlet	NSTextField*			summaryTextField;
    IBOutlet	NSProgressIndicator*	progressIndicator;
    IBOutlet	NSButton*				cancelButton;
    IBOutlet	NSTextView*				logOutputView;
    IBOutlet	NSTabView*				optionsTabsView;
    IBOutlet	NSTextField*			webserverURL;
    IBOutlet    NSWindow*               preferencesWindow;
    IBOutlet    NSWindow*               queueWindow;
    IBOutlet    NSArrayController*      settingsController;

    BOOL                    shownInitialProgressEstimatingMsg;
}

@synthesize lastProgressUpdate = _lastProgressUpdate;

-(void)awakeFromNib
{
	[super awakeFromNib];

	[self setProgressText:@""];
	[summaryTextField setStringValue:@"Idle"];
    [self showURLToServer];
			
	[[self window] setExcludedFromWindowsMenu:YES];
	[[self window] makeKeyAndOrderFront:self];	
//	[[self window] makeMainWindow];
    
    [[self window] performSelector:@selector(makeMainWindow) withObject:nil afterDelay:0.1];
    
	[[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(didPerformUIAction:)
                                                 name:NSApplicationWillBecomeActiveNotification
                                               object:nil];
    
    settingsController.content = [NSArray arrayWithObjects:
                                    [NSMutableDictionary dictionaryWithObject:@"Export" forKey:@"name"],
                                  [NSMutableDictionary dictionaryWithObject:@"Downloads" forKey:@"name"],
                                  [NSMutableDictionary dictionaryWithObject:@"Web" forKey:@"name"],
                                  nil];
}

#pragma mark UI

-(void)didQueueFile {
	[self didPerformUIAction:nil];
}

-(void)didPerformUIAction:(id)sender
{
	if ( [[self window] isVisible] == NO ) {
		[[self window] makeKeyAndOrderFront:self];
        [toggleMainWindowMenuItem setState:NSOnState];
	}
}

-(IBAction)toggleMainWindow:(id)sender
{    
	if ( [toggleMainWindowMenuItem state] == NSOnState ) {
		[[self window] orderOut:nil];
		[toggleMainWindowMenuItem setState:NSOffState];
	} else {
		[[self window] makeKeyAndOrderFront:nil];
		[toggleMainWindowMenuItem setState:NSOnState];
	}
}

-(BOOL)windowShouldClose:(id)sender
{
	BOOL	result = YES;

	[toggleMainWindowMenuItem setState:NSOffState];
	
	return( result );
}

-(BOOL)askIfIsOKToQuit
{
	BOOL	result = NO;
	
	switch ( [[NSAlert alertWithMessageText:@"Are you sure you want to Quit?"
							defaultButton:@"Cancel"
							alternateButton:@"Quit"
							otherButton:nil
							informativeTextWithFormat:@"The application is busy exporting. If you quit the export will be stopped."] runModal] ) {

		// Cancel
		case NSAlertDefaultReturn:
			result = NO;
			break;
		
		// Quit
		case  NSAlertAlternateReturn:
		{
			[self cancelAction:self];
			[[HBVideoEncoder sharedInstance] hbTerminated:nil];
		} 
		result = YES;
		break;
	}
	
	return( result );
}

-(void)setupPrefs
{
    NSToolbar*  toolbar = [preferencesWindow toolbar];
    
 //   [toolbar setDisplayMode:NSToolbarDisplayMode];
    
    for ( NSToolbarItem* item in [toolbar items] ) {
        
        if ( [item tag] == 0 ) {
            [item setImage:[[NSWorkspace sharedWorkspace] iconForFileType:NSFileTypeForHFSTypeCode(kToolbarMovieFolderIcon)]];
        } else
        if ( [item tag] == 1 ) {
            [item setImage:[[NSWorkspace sharedWorkspace] iconForFileType:NSFileTypeForHFSTypeCode(kToolbarDownloadsFolderIcon)]];
        } else
        if ( [item tag] == 2 ) {
            [item setImage:[[NSWorkspace sharedWorkspace] iconForFileType:NSFileTypeForHFSTypeCode(kInternetLocationHTTPIcon)]];
        }        
        
    }
}

-(IBAction)toolbarClick:(id)sender
{
    [optionsTabsView selectTabViewItem:[optionsTabsView tabViewItemAtIndex:[sender tag]]];
    [sender setEnabled:YES];
}

-(IBAction)finishPreferences:(id)sender
{
    [NSApp endSheet:preferencesWindow];
    [preferencesWindow orderOut:nil];
}

-(IBAction)showPreferences:(id)sender {
    [self setupPrefs];
    [NSApp beginSheet:preferencesWindow modalForWindow:[self window] modalDelegate:self didEndSelector:nil contextInfo:nil];
}

-(IBAction)finishQueue:(id)sender
{
    [NSApp endSheet:queueWindow];
    [queueWindow orderOut:nil];
}

-(IBAction)showQueue:(id)sender {
    [NSApp beginSheet:queueWindow modalForWindow:[self window] modalDelegate:self didEndSelector:nil contextInfo:nil];
}

-(void)startProgress
{
	[progressIndicator startAnimation:self];
	[cancelButton setEnabled:YES];
	[[HBVideoEncoder sharedInstance] setUserCanceled:NO];
    shownInitialProgressEstimatingMsg = NO;
}

-(void)finishedProgress
{
	[progressIndicator setDoubleValue:0.0];
	[progressIndicator stopAnimation:self];
	[cancelButton setEnabled:NO];

	[[NSApp dockTile] setBadgeLabel:@""];
	
	[[NSSound soundNamed:@"Pop"] play];
}

-(IBAction)cancelAction:(id)sender
{
	[[HBVideoEncoder sharedInstance] cancel];
	[[HBVideoEncoder sharedInstance] setUserCanceled:YES];
	[self setProgressText:@""];
	[summaryTextField setStringValue:@"Idle"];
}

-(void)setSummaryText:(NSString*)filePath
{
	NSString*	fileName = [[filePath lastPathComponent] stringByDeletingPathExtension];
	fileName = [fileName stringByReplacingOccurrencesOfString:@"." withString:@" "];
	
	[summaryTextField setStringValue:fileName];
}

-(void)setProgressText:(NSString*)string
{
#ifdef DEBUG
//    NSLog(@"setProgressText: %@", string);
#endif
    
	[progressTextField setStringValue:string];
	[[progressTextField window] display];
}

-(void)setProgressDoubleValue:(double)value
{
    [progressIndicator setDoubleValue:value];
}

#pragma mark Queue View

-(id)hyperlinkFromString:(NSString*)inString withURL:(NSURL*)aURL
{
    NSMutableAttributedString* attrString = [[NSMutableAttributedString alloc] initWithString: inString];
    NSRange range = NSMakeRange(0, [attrString length]);
    
    [attrString beginEditing];
    
    [attrString addAttribute:NSFontAttributeName value:[NSFont fontWithName:@"LucidaGrande" size:12] range:range];			

    [attrString addAttribute:NSLinkAttributeName value:[aURL absoluteString] range:range];
    
    // make the text appear in blue
    [attrString addAttribute:NSForegroundColorAttributeName value:[NSColor blueColor] range:range];
    
    // next make the text appear with an underline
    [attrString addAttribute:
     NSUnderlineStyleAttributeName value:[NSNumber numberWithInt:NSSingleUnderlineStyle] range:range];
    
    [attrString endEditing];
    
    return attrString;
}

-(void)showURLToServer
{
    NSString*   address = @"";
    
    // Get first ipv4 addr...
    for ( NSString *addr in [[NSHost currentHost] addresses] ) {
        NSArray *components = [addr componentsSeparatedByString:@"."];
        if ( [components count] == 4 ) {
            address = addr;
            break;
        }
    }
    
    NSString*   url = [NSString stringWithFormat:@"http://%@:%d", address, (int)PreferenceIntegerForKey(kWebServerPort) ];
    
    [webserverURL setAllowsEditingTextAttributes: YES];
    [webserverURL setSelectable: YES];
    [webserverURL setAttributedStringValue:[self hyperlinkFromString:url withURL:[NSURL URLWithString:url]]];
}

@end
