//
//  Encoder.h
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
 
#import <Cocoa/Cocoa.h>

@protocol HBVideoEncoderDelegate;

@interface HBVideoEncoder : NSObject
@property (assign)	BOOL					userCanceled;
@property (strong)	NSURL*					originalMovie;
@property (assign)  double                  lastProgressPercentage;

+(HBVideoEncoder*)sharedInstance;

-(BOOL)isBusy;
-(BOOL)askIfIsOKToQuit;

-(void)addToQueue:(NSString*)fullPath;
-(void)convertNextFileInQueue;
-(NSArray*)displayNamesOfItemsInQueue;

-(void)cancel;
-(void)hbReadNotify:(NSNotification*)notification;
-(void)hbTerminated:(NSNotification *)aNotification;
-(void)convert:(NSString *)filePath;
-(void)addToTunes:(NSURL*)file;

-(void)processProgressStringFromHB:(NSString*)text;

-(void)alertIfHBCannotBeFound;
-(NSString*)pathToHandbreakCLI;

-(NSString*)cleanupName:(NSString*)name;

@end

@protocol HBVideoEncoderDelegate <NSObject>
-(BOOL)askIfIsOKToQuit;
-(void)startProgress;
-(void)finishedProgress;
-(void)setProgressDoubleValue:(double)value;
-(void)setSummaryText:(NSString*)filePath;
-(void)setProgressText:(NSString*)string;
-(void)didQueueFile;
-(void)didPerformUIAction:(id)sender;
@end