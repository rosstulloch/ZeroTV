//
//  RecentDownloads.h
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
 
#import <Cocoa/Cocoa.h>

@interface RecentDownloads : NSObject
@property (strong) NSMenu* recentDownloads;

+(RecentDownloads*)sharedInstance;

-(void)awakeFromNib;
-(void)startWatchingDownloadsFolder;
-(void)buildRecentDownloadsMenuInThread;
-(void)buildRecentDownloadsMenuThreadEntry:(id)arg;
-(void)buildRecentDownloadsMenuWithItems:(NSArray*)urls;
-(NSArray*)scanForVideoFiles:(NSURL *)directoryToScan applyExclusions:(BOOL)filterResults;

@end

void	RecentDownloadsFSEventStreamCallback( ConstFSEventStreamRef	streamRef,
									void					*clientCallBackInfo,
									size_t					numEvents,
									void					*eventPaths,
									const					FSEventStreamEventFlags eventFlags[],
									const					FSEventStreamEventId eventIds[]);