/*
 File: SessionManager.m
 Abstract: Manages the GKSession and GKVoiceChatService.  While the game is
 running, it transfers game packets to and from the game and the peer.
 Version: 1.0
 
 Disclaimer: IMPORTANT:  This Apple software is supplied to you by Apple
 Inc. ("Apple") in consideration of your agreement to the following
 terms, and your use, installation, modification or redistribution of
 this Apple software constitutes acceptance of these terms.  If you do
 not agree with these terms, please do not use, install, modify or
 redistribute this Apple software.
 
 In consideration of your agreement to abide by the following terms, and
 subject to these terms, Apple grants you a personal, non-exclusive
 license, under Apple's copyrights in this original Apple software (the
 "Apple Software"), to use, reproduce, modify and redistribute the Apple
 Software, with or without modifications, in source and/or binary forms;
 provided that if you redistribute the Apple Software in its entirety and
 without modifications, you must retain this notice and the following
 text and disclaimers in all such redistributions of the Apple Software.
 Neither the name, trademarks, service marks or logos of Apple Inc. may
 be used to endorse or promote products derived from the Apple Software
 without specific prior written permission from Apple.  Except as
 expressly stated in this notice, no other rights or licenses, express or
 implied, are granted by Apple herein, including but not limited to any
 patent rights that may be infringed by your derivative works or by other
 works in which the Apple Software may be incorporated.
 
 The Apple Software is provided by Apple on an "AS IS" basis.  APPLE
 MAKES NO WARRANTIES, EXPRESS OR IMPLIED, INCLUDING WITHOUT LIMITATION
 THE IMPLIED WARRANTIES OF NON-INFRINGEMENT, MERCHANTABILITY AND FITNESS
 FOR A PARTICULAR PURPOSE, REGARDING THE APPLE SOFTWARE OR ITS USE AND
 OPERATION ALONE OR IN COMBINATION WITH YOUR PRODUCTS.
 
 IN NO EVENT SHALL APPLE BE LIABLE FOR ANY SPECIAL, INDIRECT, INCIDENTAL
 OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
 SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
 INTERRUPTION) ARISING IN ANY WAY OUT OF THE USE, REPRODUCTION,
 MODIFICATION AND/OR DISTRIBUTION OF THE APPLE SOFTWARE, HOWEVER CAUSED
 AND WHETHER UNDER THEORY OF CONTRACT, TORT (INCLUDING NEGLIGENCE),
 STRICT LIABILITY OR OTHERWISE, EVEN IF APPLE HAS BEEN ADVISED OF THE
 POSSIBILITY OF SUCH DAMAGE.
 
 Copyright (C) 2010 Apple Inc. All Rights Reserved.
 
 */

#import <AudioToolbox/AudioToolbox.h>
#import "SessionManager.h"

//#define SESSION_ID @"gkrocket"

@implementation SessionManager
@synthesize currentConfPeerID;
@synthesize peerList;
@synthesize lobbyDelegate;
@synthesize gameDelegate;
@synthesize session = myGKSession;

#pragma mark -
#pragma mark NSObject Methods

- (id)init 
{
	if (self = [super init]) {
        // Peers need to have the same sessionID set on their GKSession to see each other.
	//	sessionID = SESSION_ID; 
		peerList = [[NSMutableArray alloc] init];
        
        // Set up starting/stopping session on application hiding/terminating
        [[NSNotificationCenter defaultCenter] addObserver:self
                                              selector:@selector(willTerminate:)
                                              name:UIApplicationWillTerminateNotification
                                              object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                              selector:@selector(willTerminate:)
                                              name:UIApplicationWillResignActiveNotification
                                              object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                              selector:@selector(willResume:)
                                              name:UIApplicationDidBecomeActiveNotification
                                              object:nil];
        
        [self setupVoice];
	}
	return self;  
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [GKVoiceChatService defaultVoiceChatService].client = nil;
    if (myGKSession) [self destroySession];
	myGKSession = nil;
	sessionID = nil; 
	[peerList release]; 
    [super dealloc];
}

#pragma mark -
#pragma mark Session logic

// Creates a GKSession and advertises availability to Peers
- (void) setupSession: (NSString*) sID
{
	sessionID = sID;
	
	// GKSession will default to using the device name as the display name
	myGKSession = [[GKSession alloc] initWithSessionID:sessionID displayName:nil sessionMode:GKSessionModePeer];
	myGKSession.delegate = self; 
	[myGKSession setDataReceiveHandler:self withContext:nil]; 
	myGKSession.available = YES;
    sessionState = ConnectionStateDisconnected;
    [lobbyDelegate peerListDidChange:self];
}

// Initiates a GKSession connection to a selected peer.
-(void) connect:(NSString *) peerID
{
	[myGKSession connectToPeer:peerID withTimeout:10.0];
    self.currentConfPeerID = peerID;
    sessionState = ConnectionStateConnecting;
}

// Called from GameLobbyController if the user accepts the invitation alertView
-(BOOL) didAcceptInvitation
{
    NSError *error = nil;
    if (![myGKSession acceptConnectionFromPeer:currentConfPeerID error:&error]) {
        NSLog(@"%@",[error localizedDescription]);
    }
    
    return (gameDelegate == nil);
}

// Called from GameLobbyController if the user declines the invitation alertView
-(void) didDeclineInvitation
{
    // Deny the peer.
    if (sessionState != ConnectionStateDisconnected) {
        [myGKSession denyConnectionFromPeer:currentConfPeerID];
		[currentConfPeerID release];
        currentConfPeerID = nil;
        sessionState = ConnectionStateDisconnected;
    }
    // Go back to the lobby if the game screen is open.
    [gameDelegate willDisconnect:self];
}

-(BOOL) comparePeerID:(NSString*)peerID
{
    return [peerID compare:myGKSession.peerID] == NSOrderedAscending;
}

// Called to check if the session is ready to start a voice chat.
-(BOOL) isReadyToStart
{
    return sessionState == ConnectionStateConnected;
}

// When the voice chat starts, tell the game it can begin.
-(void) voiceChatDidStart
{
    [gameDelegate session:self didConnectAsInitiator:![self comparePeerID:currentConfPeerID]];
}

// Called by RocketController and VoiceManager to send data to the peer
-(void) sendPacket:(NSData*)data ofType:(PacketType)type
{
    NSMutableData * newPacket = [NSMutableData dataWithCapacity:([data length]+sizeof(uint32_t))];
    // Both game and voice data is prefixed with the PacketType so the peer knows where to send it.
    uint32_t swappedType = CFSwapInt32HostToBig((uint32_t)type);
    [newPacket appendBytes:&swappedType length:sizeof(uint32_t)];
    [newPacket appendData:data];
	
	NSString* peerID = currentConfPeerID;
	NSLog(@"Session: %@", myGKSession.peerID);
	NSLog(@"toPeers: %@", peerID);
	
    NSError *error;
  	if (![myGKSession sendData:newPacket toPeers:[NSArray arrayWithObject:peerID] withDataMode:GKSendDataReliable error:&error]) {
        NSLog(@"%@",[error localizedDescription]);
    }
}

// Clear the connection states in the event of leaving a call or error.
-(void) disconnectCurrentCall
{	
    [gameDelegate willDisconnect:self];
    if (sessionState != ConnectionStateDisconnected) {
        if(sessionState == ConnectionStateConnected) {		
            [[GKVoiceChatService defaultVoiceChatService] stopVoiceChatWithParticipantID:currentConfPeerID];
        }
        // Don't leave a peer hangin'
        if (sessionState == ConnectionStateConnecting) {
            [myGKSession cancelConnectToPeer:currentConfPeerID];
        }
        [myGKSession disconnectFromAllPeers];
        myGKSession.available = YES;
        sessionState = ConnectionStateDisconnected;
		[currentConfPeerID release];
        currentConfPeerID = nil;
    }
}

// Application is exiting or becoming inactive, end the session.
- (void)destroySession
{
    [self disconnectCurrentCall];
	myGKSession.delegate = nil;
	[myGKSession setDataReceiveHandler:nil withContext:nil];
	[myGKSession release];
    [peerList removeAllObjects];
}

// Called when notified the application is exiting or becoming inactive.
- (void)willTerminate:(NSNotification *)notification
{
    [self destroySession];
}

// Called after the app comes back from being hidden by something like a phone call.
- (void)willResume:(NSNotification *)notification
{
    [self setupSession: sessionID];
}

#pragma mark -
#pragma mark GKSessionDelegate Methods and Helpers

// Received an invitation.  If we aren't already connected to someone, open the invitation dialog.
- (void)session:(GKSession *)session didReceiveConnectionRequestFromPeer:(NSString *)peerID
{
	NSLog(@"didReceiveConnectionRequestFromPeer %@", peerID);
	
    if (sessionState == ConnectionStateDisconnected) {
        currentConfPeerID = [peerID retain];
        sessionState = ConnectionStateConnecting;
        [lobbyDelegate didReceiveInvitation:self fromPeer:[myGKSession displayNameForPeer:peerID]];
    } else {
        [myGKSession denyConnectionFromPeer:peerID];
    }
}

// Unable to connect to a session with the peer, due to rejection or exiting the app
- (void)session:(GKSession *)session connectionWithPeerFailed:(NSString *)peerID withError:(NSError *)error
{
    NSLog(@"connectionWithPeerFailed %@",[error localizedDescription]);
    if (sessionState != ConnectionStateDisconnected) {
        [lobbyDelegate invitationDidFail:self fromPeer:[myGKSession displayNameForPeer:peerID]];
        // Make self available for a new connection.
		[currentConfPeerID release];
        currentConfPeerID = nil;
        myGKSession.available = YES;
        sessionState = ConnectionStateDisconnected;
    }
}

// The running session ended, potentially due to network failure.
- (void)session:(GKSession *)session didFailWithError:(NSError*)error
{
    NSLog(@"%@",[error localizedDescription]);
    [self disconnectCurrentCall];
}

// React to some activity from other peers on the network.
- (void)session:(GKSession *)session peer:(NSString *)peerID didChangeState:(GKPeerConnectionState)state
{
	NSLog(@"didChangeState session Peer ID: %@", session.peerID);
	NSLog(@"didChangeState Peer ID: %@", peerID);
	NSLog(@"state: %d", state);
	
	switch (state) { 
		case GKPeerStateAvailable:
            // A peer became available by starting app, exiting settings, or ending a call.
			if (![peerList containsObject:peerID]) {
				[peerList addObject:peerID]; 
			}
 			[lobbyDelegate peerListDidChange:self]; 
			break;
		case GKPeerStateUnavailable:
            // Peer unavailable due to joining a call, leaving app, or entering settings.
            [peerList removeObject:peerID]; 
            [lobbyDelegate peerListDidChange:self]; 
			break;
		case GKPeerStateConnected:
            // Connection was accepted, set up the voice chat.
            currentConfPeerID = [peerID retain];
            myGKSession.available = NO;
            [gameDelegate voiceChatWillStart:self];
            sessionState = ConnectionStateConnected;
            // Compare the IDs to decide which device will invite the other to a voice chat.
            if([self comparePeerID:peerID]) {
                NSError *error; 
                if (![[GKVoiceChatService defaultVoiceChatService] startVoiceChatWithParticipantID:peerID error:&error]) {
                    NSLog(@"%@",[error localizedDescription]);
                }
            }
			break;				
		case GKPeerStateDisconnected:
            // The call ended either manually or due to failure somewhere.
            [self disconnectCurrentCall];
            [peerList removeObject:peerID]; 
            [lobbyDelegate peerListDidChange:self];
			break;
        case GKPeerStateConnecting:
            // Peer is attempting to connect to the session.
            break;
		default:
			break;
	}
}

// Called when voice or game data is received over the network from the peer
- (void) receiveData:(NSData *)data fromPeer:(NSString *)peer inSession:(GKSession *)session context:(void *)context
{
    PacketType header;
    uint32_t swappedHeader;
    if ([data length] >= sizeof(uint32_t)) {    
        [data getBytes:&swappedHeader length:sizeof(uint32_t)];
        header = (PacketType)CFSwapInt32BigToHost(swappedHeader);
        NSRange payloadRange = {sizeof(uint32_t), [data length]-sizeof(uint32_t)};
        NSData* payload = [data subdataWithRange:payloadRange];
        
		NSLog(@"SessionManager receive data");
		
        // Check the header to see if this is a voice or a game packet
        if (header == PacketTypeVoice) {
            [[GKVoiceChatService defaultVoiceChatService] receivedData:payload fromParticipantID:peer];
        } else {
            [gameDelegate session:self didReceivePacket:payload ofType:header];
        }
    }
}

- (NSString *) displayNameForPeer:(NSString *)peerID
{
	return [myGKSession displayNameForPeer:peerID];
}

@end

#pragma mark -
#pragma mark AudioSession Setup

// Sets up the audio session to use the speakerphone
void EnableSpeakerPhone ()
{
	UInt32 dataSize = sizeof(CFStringRef);
	CFStringRef currentRoute = NULL;
    OSStatus result = noErr;
    
	AudioSessionGetProperty(kAudioSessionProperty_AudioRoute, &dataSize, &currentRoute);
    
	// Set the category to use the speakers and microphone.
    UInt32 sessionCategory = kAudioSessionCategory_PlayAndRecord;
    result = AudioSessionSetProperty (
                                      kAudioSessionProperty_AudioCategory,
                                      sizeof (sessionCategory),
                                      &sessionCategory
                                      );	
    assert(result == kAudioSessionNoError);
    
    Float64 sampleRate = 44100.0;
    dataSize = sizeof(sampleRate);
    result = AudioSessionSetProperty (
                                      kAudioSessionProperty_PreferredHardwareSampleRate,
                                      dataSize,
                                      &sampleRate
                                      );
    assert(result == kAudioSessionNoError);
    
	// Default to speakerphone if a headset isn't plugged in.
    UInt32 route = kAudioSessionOverrideAudioRoute_Speaker;
    dataSize = sizeof(route);
    result = AudioSessionSetProperty (
                                      // This requires iPhone OS 3.1
                                      kAudioSessionProperty_OverrideCategoryDefaultToSpeaker,
                                      dataSize,
                                      &route
                                      );
    assert(result == kAudioSessionNoError);
    
    AudioSessionSetActive(YES);
}

// Called when audio is interrupted by a call or alert.  Since we are using
// UIApplicationWillResignActiveNotification to deal with ending the game,
// this just resumes speakerphone after an audio interruption.
void InterruptionListenerCallback (void *inUserData, UInt32 interruptionState)
{
    if (interruptionState == kAudioSessionEndInterruption) {
        EnableSpeakerPhone();
    }
}

@implementation SessionManager (VoiceManager)

- (void)setupVoice
{
    // Set up audio to default to speakerphone but use the headset if one is plugged in.
    AudioSessionInitialize(NULL, NULL, InterruptionListenerCallback, self);
    EnableSpeakerPhone();
    
    [GKVoiceChatService defaultVoiceChatService].client = self; 
	[[GKVoiceChatService defaultVoiceChatService] setInputMeteringEnabled:YES]; 
	[[GKVoiceChatService defaultVoiceChatService] setOutputMeteringEnabled:YES];
}

// GKVoiceChatService Client Method. For convenience, we are using the same ID for the GKSession and GKVoiceChatService.
- (NSString *)participantID
{
	return myGKSession.peerID;
}

// GKVoiceChatService Client Method. Sends voice data over the GKSession to the peer.
- (void)voiceChatService:(GKVoiceChatService *)voiceChatService sendData:(NSData *)data toParticipantID:(NSString *)participantID
{
  	[self sendPacket:data ofType:PacketTypeVoice]; 
}

// GKVoiceChatService Client Method. Received a voice chat invitation from the connected peer.
- (void)voiceChatService:(GKVoiceChatService *)voiceChatService didReceiveInvitationFromParticipantID:(NSString *)participantID callID:(NSInteger)callID
{
	if ([self isReadyToStart]) {
		NSError *error;
		if (![[GKVoiceChatService defaultVoiceChatService] acceptCallID:callID error:&error]) {
            NSLog(@"%@",[error localizedDescription]);
            [self disconnectCurrentCall];
        }
	} else {
		[[GKVoiceChatService defaultVoiceChatService] denyCallID:callID];
		[self disconnectCurrentCall];
	}
}

// GKVoiceChatService Client Method. In the event something weird happened and the voice chat failed, disconnect.
- (void)voiceChatService:(GKVoiceChatService *)voiceChatService didNotStartWithParticipantID:(NSString *)participantID error:(NSError *)error
{
    NSLog(@"%@",[error localizedDescription]);
    [self disconnectCurrentCall];
}

// GKVoiceChatService Client Method. The voice chat with the connected peer successfully started.
- (void)voiceChatService:(GKVoiceChatService *)voiceChatService didStartWithParticipantID:(NSString *)participantID
{
    // Since the session and voice chat are up, we can tell the game to start.
    [self voiceChatDidStart]; 
}

@end
