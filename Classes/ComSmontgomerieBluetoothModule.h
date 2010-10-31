/**
 * Your Copyright Here
 *
 * Appcelerator Titanium is Copyright (c) 2009-2010 by Appcelerator, Inc.
 * and licensed under the Apache Public License (version 2)
 */
#import "TiModule.h"
#import <GameKit/GameKit.h>

@interface ComSmontgomerieBluetoothModule : TiModule <GKPeerPickerControllerDelegate, GKSessionDelegate, UIAlertViewDelegate> 
{
	NSInteger	gameState;
	NSInteger	peerStatus;
	
	// networking
	GKSession		*gameSession;
	int				gameUniqueID;
	int				gamePacketNumber;
	NSString		*gamePeerId;
	NSDate			*lastHeartbeatDate;
	
	UIAlertView		*connectionAlert;	
}

@property(nonatomic) NSInteger		gameState;
@property(nonatomic) NSInteger		peerStatus;

@property(nonatomic, retain) GKSession	 *gameSession;
@property(nonatomic, copy)	 NSString	 *gamePeerId;
@property(nonatomic, retain) NSDate		 *lastHeartbeatDate;
@property(nonatomic, retain) UIAlertView *connectionAlert;

- (void)invalidateSession:(GKSession *)session;

- (void)sendNetworkPacket:(GKSession *)session packetID:(int)packetID withData:(void *)data ofLength:(int)length reliable:(BOOL)howtosend;
- (void)startPicker;
- (id)startPicker: (id) args;
	
@end
