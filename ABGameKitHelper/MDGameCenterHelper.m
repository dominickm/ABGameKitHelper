//
//  ABGameKitHelper.m
//
//  Created by Alexander Blunck on 27.02.12.
//  Copyright (c) 2012 Ablfx. All rights reserved.
//

#import <CommonCrypto/CommonCryptor.h>
#import "MDGameCenterHelper.h"

@interface MDGameCenterHelper () <GKLeaderboardViewControllerDelegate, GKAchievementViewControllerDelegate>

@property (nonatomic) BOOL matchStarted;

@end

@implementation MDGameCenterHelper

#pragma mark - Singleton
+(id)sharedHelper
{
    static MDGameCenterHelper* sharedHelper = nil;
    static dispatch_once_t once = 0;
    dispatch_once(&once, ^{sharedHelper = [[self alloc] init];});
    return sharedHelper;
}



#pragma mark - Initializer
-(id)init
{
    self = [super init];
    if (self)
    {
        [self authenticatePlayer];
    }
    return self;
}



#pragma mark - Authenticate
-(void)authenticatePlayer
{
    GKLocalPlayer* player = [GKLocalPlayer localPlayer];
    [player setAuthenticateHandler:^(UIViewController *viewController, NSError *error) {
        //
        
        if (viewController) {
            [[self topViewController] presentViewController:viewController animated:YES completion:nil];
        }
        
        if ([[GKLocalPlayer localPlayer] isAuthenticated])
        {
            self.authenticated = YES;
            if (ABGAMEKITHELPER_LOGGING) NSLog(@"ABGameKitHelper: Player successfully authenticated.");
            //Report possible cached scores / achievements
            [self reportCachedAchievements];
            [self reportCachedScores];
        }
        
        if (error)
        {
            self.authenticated = NO;
            if (ABGAMEKITHELPER_LOGGING) NSLog(@"ABGameKitHelper: ERROR -> Player didn't authenticate");
        }
    }];
}



#pragma mark - Leaderboard
-(void)reportScore:(long long)aScore forLeaderboard:(NSString *)leaderboardId
{
    GKScore *score = [[GKScore alloc] initWithCategory:leaderboardId];
    score.value = aScore;
    
    [score reportScoreWithCompletionHandler:^(NSError *error) {
        if (!error)
        {
            if (ABGAMEKITHELPER_LOGGING) NSLog(@"ABGameKitHelper: Reported score (%lli) to %@ successfully.", score.value, leaderboardId);
        }
        else
        {
            [self cacheScore:score];
            if (ABGAMEKITHELPER_LOGGING) NSLog(@"ABGameKitHelper: ERROR -> Reporting score (%lli) to %@ failed, caching...", score.value, leaderboardId);
        }
    }];
}

-(void)showLeaderboard:(NSString*)leaderboardId
{
    GKLeaderboardViewController *viewController = [GKLeaderboardViewController new];
    viewController.leaderboardDelegate = self;
    if (leaderboardId)
    {
        viewController.category = leaderboardId;
    }
    
    [[self topViewController] presentViewController:viewController animated:YES completion:nil];
}



#pragma mark - Achievements
-(void)reportAchievement:(NSString*)achievementId percentComplete:(double)percent
{
    if (percent > 100.0f) percent = 100.0f;
    
    //Mark achievement as completed locally
    if (percent == 100)
    {
        [self saveBool:YES key:achievementId];
    }
    
    GKAchievement* achievement = [[GKAchievement alloc] initWithIdentifier:achievementId];
    
    if (achievement)
    {
        achievement.percentComplete = percent;
        
        [achievement reportAchievementWithCompletionHandler:^(NSError* error) {
            if (!error)
            {
                if (ABGAMEKITHELPER_LOGGING) NSLog(@"ABGameKitHelper: Achievement (%@) with %f%% progress reported", achievement.identifier, achievement.percentComplete);
            }
            else
            {
                [self cacheAchievement:achievement];
                if (ABGAMEKITHELPER_LOGGING) NSLog(@"ABGameKitHelper: ERROR -> Reporting achievement (%@) with %f%% progress failed, caching...", achievement.identifier, achievement.percentComplete);
            }
        }];
    }
}

-(void)showAchievements
{
    GKAchievementViewController *viewController = [GKAchievementViewController new];
    viewController.achievementDelegate = self;
    
    [[self topViewController] presentViewController:viewController animated:YES completion:nil];
}

-(void)resetAchievements
{
    [GKAchievement resetAchievementsWithCompletionHandler:^(NSError* error) {
        if (!error)
        {
            if (ABGAMEKITHELPER_LOGGING) NSLog(@"ABGameKitHelper: Achievements reset successfully.");
        }
        else
        {
            if (ABGAMEKITHELPER_LOGGING) NSLog(@"ABGameKitHelper: Failed to reset achievements.");
        }
    }];
}



#pragma mark - Notifications
-(void)showNotification:(NSString *)title message:(NSString *)message identifier:(NSString *)achievementId
{
    //Show notification only if it hasn't been achieved yet
    if (![self boolForKey:achievementId])
    {
        [GKNotificationBanner showBannerWithTitle:title message:message completionHandler:nil];
    }
}



#pragma mark - Caching
#pragma mark - Caching Scores
-(void)cacheScore:(GKScore *)aScore
{
    //Retrieve cached scores
    NSMutableArray* scores = [self objectForKey:@"cachedScores"];
    
    //Add new score to array
    [scores addObject:aScore];
    
    //Save scores to persistant storage
    [self saveObject:scores key:@"cachedScores"];
}

-(void)reportCachedScores
{
    //Retrieve cached scores
    NSMutableArray* scores = [self objectForKey:@"cachedScores"];
    
    if (ABGAMEKITHELPER_LOGGING) NSLog(@"ABGameKitHelper: Attempting to report %i cached scores...", scores.count);
    
    [GKScore reportScores:scores withCompletionHandler:^(NSError *error) {
        if (!error)
        {
            [self removeAllCachedScores];
            if (ABGAMEKITHELPER_LOGGING) NSLog(@"ABGameKitHelper: Reported %i cached score(s) successfully.", scores.count);
        }
        else
        {
            if (ABGAMEKITHELPER_LOGGING) NSLog(@"ABGameKitHelper: ERROR -> Failed to report %i cached score(s).", scores.count);
        }
    }];
}

-(void)removeAllCachedScores
{
    [self saveObject:[NSMutableArray new] key:@"cachedScores"];
}


#pragma mark - Caching Achievements
-(void)cacheAchievement:(GKAchievement*)achievement
{
    //Retrieve cached achievements
    NSMutableArray *achievements = [self objectForKey:@"cachedAchievements"];
    
    //Add new achievment to array
    [achievements addObject:achievement];
    
    //Save achievement to persistant storage
    [self saveObject:achievements key:@"cachedAchievements"];
}

-(void)reportCachedAchievements
{
    //Retrieve cached achievements
    NSMutableArray* achievements = [self objectForKey:@"cachedAchievements"];
    
    if (ABGAMEKITHELPER_LOGGING) NSLog(@"ABGameKitHelper: Attempting to report %i cached achievements...", achievements.count);
    
    [GKAchievement reportAchievements:achievements withCompletionHandler:^(NSError* error) {
        if (!error)
        {
            [self removeAllCachedAchievements];
            if (ABGAMEKITHELPER_LOGGING) NSLog(@"ABGameKitHelper: Reported %i cached achievement(s) successfully.", achievements.count);
        }
        else
        {
            if (ABGAMEKITHELPER_LOGGING) NSLog(@"ABGameKitHelper: ERROR -> Failed to report %i cached achievement(s).", achievements.count);
        }
    }];
}

-(void)removeAllCachedAchievements
{
    [self saveObject:[NSMutableArray new] key:@"cachedAchievements"];
}



#pragma mark - Data Persistance
-(NSString *)filePath
{
    NSString* fileExt = @".abgk";
    NSString* fileName = [NSString stringWithFormat:@"%@%@", [[self appName] lowercaseString], fileExt];
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString* documentsDirectory = [paths objectAtIndex:0];
    NSString* path = [documentsDirectory stringByAppendingPathComponent:fileName];
    return path;
}

-(NSMutableDictionary *)dataDictionary
{
    NSData* binaryFile = [NSData dataWithContentsOfFile:[self filePath]];
    NSMutableDictionary *dictionary = nil;
    
    if (binaryFile == nil)
    {
        dictionary = [NSMutableDictionary dictionary];
    }
    else
    {
        NSData* decryptedData = [self decryptData:binaryFile withKey:SECRET_KEY];
        dictionary = [NSKeyedUnarchiver unarchiveObjectWithData:decryptedData];
    }
    
    return dictionary;
}

-(void)saveData:(NSData *)data key:(NSString *)key
{
    BOOL fileExists = [[NSFileManager defaultManager] fileExistsAtPath:[self filePath]];
    NSMutableDictionary* tempDic = nil;
    if (fileExists == NO)
    {
        tempDic = [NSMutableDictionary new];
    } else
    {
        tempDic = [self dataDictionary];
    }
    
    [tempDic setObject:data forKey:key];
    
    NSData* dicData = [NSKeyedArchiver archivedDataWithRootObject:tempDic];
    NSData* encryptedData = [self encryptData:dicData withKey:SECRET_KEY];
    [encryptedData writeToFile:[self filePath] atomically:YES];
}

-(NSData*)dataForKey:(NSString *)key
{
    NSMutableDictionary* tempDic = [self dataDictionary];
    NSData* loadedData = [tempDic objectForKey:key];
    
    if (loadedData)
    {
        return loadedData;
    }
    
    return nil;
}

-(void)saveObject:(id<NSCoding>)object key:(NSString *)key
{
    NSData* data = [NSKeyedArchiver archivedDataWithRootObject:object];
    [self saveData:data key:key];
}

-(id)objectForKey:(NSString *)key
{
    NSData *data = [self dataForKey:key];
    if (data)
    {
        return [NSKeyedUnarchiver unarchiveObjectWithData:data];
    }
    return nil;
}

-(void)saveBool:(BOOL)boolean key:(NSString *)key
{
    NSNumber *number = [NSNumber numberWithBool:boolean];
    NSData *data = [NSKeyedArchiver archivedDataWithRootObject:number];
    [self saveData:data key:key];
}

-(BOOL)boolForKey:(NSString *)key
{
    NSData* data = [self dataForKey:key];
    if (data)
    {
        return [[NSKeyedUnarchiver unarchiveObjectWithData:data] boolValue];
    }
    return NO;
}



#pragma mark - Helper
-(NSString *)appName
{
    NSString* bundlePath = [[[NSBundle mainBundle] bundleURL] lastPathComponent];
    return [[bundlePath stringByDeletingPathExtension] lowercaseString];
}

-(UIViewController *)topViewController
{
    UIViewController *topController = [UIApplication sharedApplication].keyWindow.rootViewController;
    while (topController.presentedViewController)
    {
        topController = topController.presentedViewController;
    }
    return topController;
}

-(NSData *)makeCryptedVersionOfData:(NSData*)data withKeyData:(const void*)keyData ofLength:(int) keyLength decrypt:(bool)decrypt
{
	int keySize = kCCKeySizeAES256;
    char key[kCCKeySizeAES256];
	bzero(key, sizeof(key));
	memcpy(key, keyData, keyLength > keySize ? keySize : keyLength);
    
	size_t bufferSize = [data length] + kCCBlockSizeAES128;
	void* buffer = malloc(bufferSize);
    
	size_t dataUsed;
    
	CCCryptorStatus status = CCCrypt(decrypt ? kCCDecrypt : kCCEncrypt,
									 kCCAlgorithmAES128,
									 kCCOptionPKCS7Padding | kCCOptionECBMode,
									 key, keySize,
									 NULL,
									 [data bytes], [data length],
									 buffer, bufferSize,
									 &dataUsed);
    
	switch(status)
	{
		case kCCSuccess:
			return [NSData dataWithBytesNoCopy:buffer length:dataUsed];
		default:
			if (ABGAMEKITHELPER_LOGGING) NSLog(@"ABGameKitHelper: ERROR -> Failed to encrypt!");
	}
    
	free(buffer);
	return nil;
}

- (NSData *)encryptData:(NSData*)data withKey:(NSString*)key
{
    NSData *keyData = [key dataUsingEncoding:NSUTF8StringEncoding];
	return [self makeCryptedVersionOfData:data withKeyData:[keyData bytes] ofLength:[keyData length] decrypt:false];
}

- (NSData *)decryptData:(NSData*)data withKey:(NSString*)key
{
	NSData *keyData = [key dataUsingEncoding:NSUTF8StringEncoding];
    return [self makeCryptedVersionOfData:data withKeyData:[keyData bytes] ofLength:[keyData length] decrypt:true];
}



#pragma mark - GKLeaderboardViewControllerDelegate
-(void)leaderboardViewControllerDidFinish:(GKLeaderboardViewController*)viewController
{
    [viewController dismissViewControllerAnimated:YES completion:nil];
}



#pragma mark - GKAchievementViewControllerDelegate
-(void)achievementViewControllerDidFinish:(GKAchievementViewController *)viewController
{
    [viewController dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - Matchmaking

- (void)findMatchWithMinPlayers:(int)minPlayers maxPlayers:(int)maxPlayers
				 viewController:(UIViewController *)viewController
					   delegate:(id<MDGameCenterHelper>)theDelegate
{
    if (![self isAuthenticated])
	{
		[self authenticatePlayer];
	}
	_matchStarted = NO;
	self.match = nil;
	self.presentingViewController = viewController;
	_delegate = theDelegate;
	[_presentingViewController dismissModalViewControllerAnimated:NO];
	
	GKMatchRequest* request = [[GKMatchRequest alloc] init];
	request.minPlayers = minPlayers;
	request.maxPlayers = maxPlayers;
	
	GKMatchmakerViewController *mmvc =
	[[GKMatchmakerViewController alloc] initWithMatchRequest:request];
	mmvc.matchmakerDelegate = self;
	
	[_presentingViewController presentModalViewController:mmvc animated:YES];
}

#pragma mark GKMatchDelegate

// The match received data sent from the player.
- (void)match:(GKMatch *)theMatch didReceiveData:(NSData *)data fromPlayer:(NSString *)playerID
{
    
    if (_match != theMatch)
	{
		return;
	}
    
    [_delegate match:theMatch didReceiveData:data fromPlayer:playerID];
}

// The player state changed (eg. connected or disconnected)
- (void)match:(GKMatch *)theMatch player:(NSString *)playerID didChangeState:(GKPlayerConnectionState)state {
    
    if (_match != theMatch)
	{
		return;
	}
    
    switch (state) {
        case GKPlayerStateConnected:
            NSLog(@"Player connected!");
            
            if (!_matchStarted && theMatch.expectedPlayerCount == 0)
			{
                NSLog(@"Ready to start match!");
            }
            
            break;
        case GKPlayerStateDisconnected:
            // a player just disconnected.
            NSLog(@"Player disconnected!");
            _matchStarted = NO;
            [_delegate matchEnded];
            break;
    }
    
}

// The match was unable to connect with the player due to an error.
- (void)match:(GKMatch *)theMatch connectionWithPlayerFailed:(NSString *)playerID withError:(NSError *)error {
    
    if (_match != theMatch)
	{
		return;
	}
    
    NSLog(@"Failed to connect to player with error: %@", error.localizedDescription);
    _matchStarted = NO;
    [_delegate matchEnded];
}

// connection failed or GC is having issues on Apple's end...
- (void)match:(GKMatch *)theMatch didFailWithError:(NSError *)error
{
    
    if (_match != theMatch)
	{
		return;
	}
    
    NSLog(@"Match failed with error: %@", error.localizedDescription);
    _matchStarted = NO;
    [_delegate matchEnded];
}

#pragma mark GKMatchmakerViewControllerDelegate

// Matching canceled
- (void)matchmakerViewControllerWasCancelled:(GKMatchmakerViewController *)viewController
{
    [_presentingViewController dismissModalViewControllerAnimated:YES];
}

// Matchmaking failed 
- (void)matchmakerViewController:(GKMatchmakerViewController *)viewController didFailWithError:(NSError *)error
{
    [_presentingViewController dismissModalViewControllerAnimated:YES];
    NSLog(@"Error finding match: %@", error.localizedDescription);
}

// match found
- (void)matchmakerViewController:(GKMatchmakerViewController *)viewController didFindMatch:(GKMatch *)theMatch
{
    [_presentingViewController dismissModalViewControllerAnimated:YES];
    self.match = theMatch;
    _match.delegate = self;
    if (!_matchStarted && _match.expectedPlayerCount == 0)
	{
        NSLog(@"Ready to start match!");
    }
}

@end
