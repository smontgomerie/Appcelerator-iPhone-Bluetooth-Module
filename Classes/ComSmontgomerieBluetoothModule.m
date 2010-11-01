/**
 * Your Copyright Here
 *
 * Appcelerator Titanium is Copyright (c) 2009-2010 by Appcelerator, Inc.
 * and licensed under the Apache Public License (version 2)
 */
#import "ComSmontgomerieBluetoothModule.h"
#import "TiBase.h"
#import "TiHost.h"
#import "TiUtils.h"


// GameKit Session ID for app
#define kTankSessionID @"gktank"

#define kMaxTankPacketSize 1024

typedef enum {
	NETWORK_ACK,					// no packet
	NETWORK_COINTOSS,				// decide who is going to be the server
	NETWORK_MOVE_EVENT,				// send position
	NETWORK_FIRE_EVENT,				// send fire
	NETWORK_HEARTBEAT				// send of entire state at regular intervals
} packetCodes;


@implementation ComSmontgomerieBluetoothModule

@synthesize peerStatus;
@synthesize gameSession, gamePeerId, lastHeartbeatDate, connectionAlert;

#pragma mark Internal

// this is generated for your module, please do not change it
-(id)moduleGUID
{
	return @"98126e9f-5aed-4d9f-96c0-b1faf3ab7960";
}

// this is generated for your module, please do not change it
-(NSString*)moduleId
{
	return @"com.smontgomerie.bluetooth";
}

#pragma mark Lifecycle

-(void)startup
{
	// this method is called when the module is first loaded
	// you *must* call the superclass
	[super startup];
	manager = [[SessionManager alloc] init];
	manager.gameDelegate = self;
	
	NSLog(@"[INFO] %@ loaded",self);
}

-(void)shutdown:(id)sender
{
	// this method is called when the module is being unloaded
	// typically this is during shutdown. make sure you don't do too
	// much processing here or the app will be quit forceably
	
	// you *must* call the superclass
	[super shutdown:sender];
}

#pragma mark Cleanup 

-(void)dealloc
{
	self.lastHeartbeatDate = nil;
	if(self.connectionAlert.visible) {
		[self.connectionAlert dismissWithClickedButtonIndex:-1 animated:NO];
	}
	self.connectionAlert = nil;
	
	// cleanup the session
	[self invalidateSession:self.gameSession];
	self.gameSession = nil;
	self.gamePeerId = nil;
	
	// release any resources that have been retained by the module
	[super dealloc];
}

#pragma mark Internal Memory Management

-(void)didReceiveMemoryWarning:(NSNotification*)notification
{
	// optionally release any resources that can be dynamically
	// reloaded once memory is available - such as caches
	[super didReceiveMemoryWarning:notification];
}

#pragma mark Listener Notifications

-(void)_listenerAdded:(NSString *)type count:(int)count
{
	if (count == 1 && [type isEqualToString:@"my_event"])
	{
		// the first (of potentially many) listener is being added 
		// for event named 'my_event'
	}
}

-(void)_listenerRemoved:(NSString *)type count:(int)count
{
	if (count == 0 && [type isEqualToString:@"my_event"])
	{
		// the last listener called for event named 'my_event' has
		// been removed, we can optionally clean up any resources
		// since no body is listening at this point for that event
	}
}

#pragma Public APIs

-(id)example:(id)args
{
	// example method
	return @"hello world";
}

-(id)exampleProp
{
	// example property getter
	return @"hello world 2";
}

-(void)exampleProp:(id)value
{
	// example property setter
}

#pragma mark -
#pragma mark Peer Picker Related Methods

-(void)startPicker
{
	[self startPicker: nil];
}

-(id)startPicker: (id) args {
	if ([NSThread isMainThread])
	{
		NSLog(@"Showing picker..");
		
		GKPeerPickerController*		picker;
		
		picker = [[GKPeerPickerController alloc] init]; // note: picker is released in various picker delegate methods when picker use is done.
		picker.delegate = self;
		[picker show]; // show the Peer Picker		
	}
	else {
		
		[self performSelectorOnMainThread:@selector(startPicker:) withObject:nil waitUntilDone:NO];		
	}
	
	return nil;
}

#pragma mark GKPeerPickerControllerDelegate Methods

- (void)peerPickerControllerDidCancel:(GKPeerPickerController *)picker { 
	// Peer Picker automatically dismisses on user cancel. No need to programmatically dismiss.
    
	// autorelease the picker. 
	picker.delegate = nil;
    [picker autorelease]; 
	
	// invalidate and release game session if one is around.
	if(self.gameSession != nil)	{
		[self invalidateSession:self.gameSession];
		self.gameSession = nil;
	}
} 

/*
 *	Note: No need to implement -peerPickerController:didSelectConnectionType: delegate method since this app does not support multiple connection types.
 *		- see reference documentation for this delegate method and the GKPeerPickerController's connectionTypesMask property.
 */

//
// Provide a custom session that has a custom session ID. This is also an opportunity to provide a session with a custom display name.
//
- (GKSession *)peerPickerController:(GKPeerPickerController *)picker sessionForConnectionType:(GKPeerPickerConnectionType)type { 
	
// TODO
	[manager setupSession: kTankSessionID];
	return manager.session;
	
	//GKSession *session = [[GKSession alloc] initWithSessionID:kTankSessionID displayName:nil sessionMode:GKSessionModePeer]; 
	// return [session autorelease]; // peer picker retains a reference, so autorelease ours so we don't leak.
}

- (void)peerPickerController:(GKPeerPickerController *)picker didConnectPeer:(NSString *)peerID toSession:(GKSession *)session { 
	NSLog(@"Did connect to peer %@", peerID);
	
	// Remember the current peer.
	self.gamePeerId = peerID;  // copy
	
	[manager connect:[peerID retain]]; 
	manager.session = session;
	
	// Make sure we have a reference to the game session and it is set up
	self.gameSession = session; // retain
	self.gameSession.delegate = manager; 
	[self.gameSession setDataReceiveHandler:manager withContext:NULL];
	
	// Done with the Peer Picker so dismiss it.
	[picker dismiss];
	picker.delegate = nil;
	[picker autorelease];
	
	NSDictionary *event = [NSDictionary dictionaryWithObjectsAndKeys:
						   peerID, @"peerID",
						   nil];
	[self fireEvent:@"didConnect" withObject:event];
} 

#pragma mark -
#pragma mark Session Related Methods

//
// invalidate session
//
- (void)invalidateSession:(GKSession *)session {
	if(session != nil) {
		[session disconnectFromAllPeers]; 
		session.available = NO; 
		[session setDataReceiveHandler: nil withContext: NULL]; 
		session.delegate = nil; 
	}
}

#pragma mark Data Send/Receive Methods

	 
-(void) session:(SessionManager*) sessionManager didReceivePacket: (NSData*) payload ofType:(PacketType) header
 {
	 // Check the header to see if this is a voice or a game packet
	 if (header == PacketTypeVoice) {
		 [[GKVoiceChatService defaultVoiceChatService] receivedData:payload fromParticipantID:sessionManager.currentConfPeerID];
	 } else {
		 
		 NSString* string = [[NSString alloc] initWithData: payload encoding: NSASCIIStringEncoding];

		 NSLog(@"Fire Event: data: %@", string);
		 
		 NSDictionary *event = [NSDictionary dictionaryWithObjectsAndKeys:
								string, @"data",
								nil];
		 [self fireEvent:@"receive" withObject:event];
	 } 
 }

- (void) voiceChatWillStart:(SessionManager *)session
{
	NSLog(@"voicechatwillstart");
}

- (void) session:(SessionManager *)session didConnectAsInitiator:(BOOL)shouldStart
{
	NSLog(@"didConnectAsInitiator");
}

- (void) willDisconnect:(SessionManager *)session
{
	NSLog(@"willDisconnect");
}

/*
 * Getting a data packet. This is the data receive handler method expected by the GKSession. 
 * We set ourselves as the receive data handler in the -peerPickerController:didConnectPeer:toSession: method.
 */
- (void)receiveData:(NSData *)data fromPeer:(NSString *)peer inSession:(GKSession *)session context:(void *)context { 
	NSLog(@"Received");
	
	PacketType header;
    uint32_t swappedHeader;
    if ([data length] >= sizeof(uint32_t)) {    
        [data getBytes:&swappedHeader length:sizeof(uint32_t)];
        header = (PacketType)CFSwapInt32BigToHost(swappedHeader);
        NSRange payloadRange = {sizeof(uint32_t), [data length]-sizeof(uint32_t)};
        NSData* payload = [data subdataWithRange:payloadRange];
		NSString* string = [[NSString alloc] initWithData: payload];
        
		NSLog(@"Data: %@", string);

        // Check the header to see if this is a voice or a game packet
        if (header == PacketTypeVoice) {
            [[GKVoiceChatService defaultVoiceChatService] receivedData:payload fromParticipantID:peer];
        } else {

			NSLog(@"Fire Event: data: %@", string);

			NSDictionary *event = [NSDictionary dictionaryWithObjectsAndKeys:
								   string, @"data",
								   nil];
			[self fireEvent:@"receive" withObject:event];
        }
    }
	
	/*
	lastPacketTime = packetTime;
	switch( packetID ) {
		case NETWORK_COINTOSS:
		{
			// coin toss to determine roles of the two players
//			int coinToss = pIntData[2];

			
			// after 1 second fire method to hide the label
//			[NSTimer scheduledTimerWithTimeInterval:2.0 target:self selector:@selector(hideGameLabel:) userInfo:nil repeats:NO];
		}
			break;
		case NETWORK_MOVE_EVENT:
		{

		}
			break;
		case NETWORK_FIRE_EVENT:
		{
		}
			break;
		case NETWORK_HEARTBEAT:
		{
			// update heartbeat timestamp
			self.lastHeartbeatDate = [NSDate date];
			
			// if we were trying to reconnect, set the state back to multiplayer as the peer is back
			if(self.gameState == kStateMultiplayerReconnect) {
				if(self.connectionAlert && self.connectionAlert.visible) {
					[self.connectionAlert dismissWithClickedButtonIndex:-1 animated:YES];
				}
				self.gameState = kStateMultiplayer;
			}
		}
			break;
		default:
			// error
			break;
	}
	*/
	
}

/* Public API method */
- (void)send: (id) args
{
	ENSURE_SINGLE_ARG(args, NSDictionary);
	ENSURE_TYPE_OR_NIL(args,NSDictionary);
	
	NSString * data = [args objectForKey:@"data"];
	ENSURE_CLASS_OR_NIL(data,[NSString class]);
	
	NSNumber* type = [args objectForKey:@"type"];
	ENSURE_CLASS_OR_NIL(type, [NSNumber class]);
	
	if ( type == NULL )
	{
		type = [[NSNumber alloc] initWithInt:PacketTypeStart];
	}
	
	NSLog(@"args: %@", args);
	NSLog(@"Sending: %@", data);
	
//	NSString * reliableStr = [self valueForUndefinedKey:@"reliable"];
//	ENSURE_CLASS_OR_NIL(reliableStr,[NSString class]);
	
	//bool reliable = (reliableStr == NULL) || ([reliableStr isEqualToString: @"true"]);
	
//	static unsigned char networkPacket[kMaxTankPacketSize];

/*	NSUInteger usedLength = data.length;
	NSRange range = NSRangeFromString(data);
	[data getBytes:&networkPacket maxLength:kMaxTankPacketSize 
			usedLength:&usedLength encoding:NSASCIIStringEncoding 
		   options:NSStringEncodingConversionAllowLossy range:range
			remainingRange:NULL];
*/	
//    NSData *packet = [[NSData alloc] initWithBytes:&networkPacket length:usedLength];	
    NSData *packet = [data dataUsingEncoding: NSASCIIStringEncoding];
	
	manager.currentConfPeerID = gamePeerId;
	[manager sendPacket: packet ofType: [type intValue]];
	
//	[self sendNetworkPacket:gameSession packetID:NETWORK_HEARTBEAT withData:&networkPacket ofLength:usedLength reliable:reliable];
}

/*
- (void)sendNetworkPacket:(GKSession *)session packetID:(int)packetID withData:(void *)data ofLength:(int)length reliable:(BOOL)howtosend {
	// the packet we'll send is resued
	static unsigned char networkPacket[kMaxTankPacketSize];
	const unsigned int packetHeaderSize = 2 * sizeof(int); // we have two "ints" for our header
	
	if(length < (kMaxTankPacketSize - packetHeaderSize)) { // our networkPacket buffer size minus the size of the header info
		int *pIntData = (int *)&networkPacket[0];
		// header info
		pIntData[0] = gamePacketNumber++;
		pIntData[1] = packetID;
		// copy data in after the header
		memcpy( &networkPacket[packetHeaderSize], data, length ); 
		
		NSData *packet = [NSData dataWithBytes: networkPacket length: (length+8)];
		if(howtosend == YES) { 
			[session sendData:packet toPeers:[NSArray arrayWithObject:gamePeerId] withDataMode:GKSendDataReliable error:nil];
		} else {
			[session sendData:packet toPeers:[NSArray arrayWithObject:gamePeerId] withDataMode:GKSendDataUnreliable error:nil];
		}
	}
}
 */

	 
MAKE_SYSTEM_PROP(VOICE,PacketTypeVoice);
MAKE_SYSTEM_PROP(START,PacketTypeStart);


@end
