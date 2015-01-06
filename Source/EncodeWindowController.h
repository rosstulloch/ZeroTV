//
//  EncodeController.h
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
 
#import <Cocoa/Cocoa.h>
#import "HBVideoEncoder.h"

@interface EncodeWindowController : NSWindowController <HBVideoEncoderDelegate>
@property (assign)	time_t			lastProgressUpdate;

-(void)awakeFromNib;
-(BOOL)askIfIsOKToQuit;

-(void)startProgress;
-(void)finishedProgress;

-(void)setProgressText:(NSString*)string;
-(void)setSummaryText:(NSString*)filePath;

-(void)didPerformUIAction:(id)sender;
-(void)showURLToServer;

-(IBAction)toggleMainWindow:(id)sender;
-(IBAction)showPreferences:(id)sender;
-(IBAction)cancelAction:(id)sender;

@end
