//
//  LYRUIConversationListNotificationObserver.m
//  Pods
//
//  Created by Kevin Coleman on 9/20/14.
//
//

#import "LYRUIConversationdDataSource.h"
#import "LYRUIDataSourceChange.h"

@interface LYRUIConversationdDataSource ()

@property (nonatomic) NSArray *conversations;
@property (nonatomic) NSArray *tempIdentifiers;

@end

@implementation LYRUIConversationdDataSource

- (instancetype)initWithLayerClient:(LYRClient *)layerClient
{
    self = [super init];
    if (self) {
        self.layerClient = layerClient;
        self.identifiers = [self refreshConversations];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(didReceiveLayerObjectsDidChangeNotification:)
                                                     name:LYRClientObjectsDidChangeNotification
                                                   object:layerClient];
    }
    return self;
}

- (id)init
{
    @throw [NSException exceptionWithName:NSInternalInconsistencyException reason:@"Failed to call designated initializer." userInfo:nil];
}

- (NSArray *)refreshConversations
{
    NSSet *conversations = [self.layerClient conversationsForIdentifiers:nil];
    NSArray *sortedConversations = [conversations sortedArrayUsingDescriptors:@[[NSSortDescriptor sortDescriptorWithKey:@"lastMessage.sentAt" ascending:NO]]];
    return [sortedConversations valueForKeyPath:@"identifier"];
}

- (void)didReceiveLayerObjectsDidChangeNotification:(NSNotification *)notification;
{
    NSLog(@"NEW FUCKING CHANGES");
    [self.delegate observerWillChangeContent:self];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
        [self processLayerChangeNotification:notification completion:^(NSMutableArray *conversationArray) {
            if (conversationArray.count > 0) {
                [self processConversationChanges:conversationArray completion:^(NSArray *conversationChanges) {
                    [self dispatchChanges:conversationChanges];
                }];
            } else {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self.delegate observer:self didChangeContent:FALSE];
                });
            }
        }];
    });
}

- (void)processLayerChangeNotification:(NSNotification *)notification completion:(void(^)(NSMutableArray *conversationArray))completion
{
    NSMutableArray *conversationArray = [[NSMutableArray alloc] init];
    NSArray *changes = [notification.userInfo objectForKey:LYRClientObjectChangesUserInfoKey];
    for (NSDictionary *change in changes) {
        if ([[change objectForKey:LYRObjectChangeObjectKey] isKindOfClass:[LYRConversation class]]) {
            [conversationArray addObject:change];
        }
    }
    completion(conversationArray);
}

- (void)processConversationChanges:(NSMutableArray *)conversationChanges completion:(void(^)(NSArray *conversationChanges))completion
{
    self.tempIdentifiers = [self refreshConversations];
    NSMutableArray *updateIndexes = [[NSMutableArray alloc] init];
    NSMutableArray *changeObjects = [[NSMutableArray alloc] init];
    for (NSDictionary *conversationChange in conversationChanges) {
        LYRConversation *conversation = [conversationChange objectForKey:LYRObjectChangeObjectKey];
        NSUInteger newIndex = [self.tempIdentifiers indexOfObject:conversation.identifier];
        LYRObjectChangeType changeType = (LYRObjectChangeType)[[conversationChange objectForKey:LYRObjectChangeTypeKey] integerValue];
        switch (changeType) {
            case LYRObjectChangeTypeCreate:
                [changeObjects addObject:[LYRUIDataSourceChange changeObjectWithType:LYRUIDataSourceChangeTypeInsert newIndex:newIndex oldIndex:0]];
                break;
                
            case LYRObjectChangeTypeUpdate: {
                 NSUInteger oldIndex = [self.identifiers indexOfObject:conversation.identifier];
                if (oldIndex != newIndex) {
                    [changeObjects addObject:[LYRUIDataSourceChange changeObjectWithType:LYRUIDataSourceChangeTypeMove newIndex:newIndex oldIndex:oldIndex]];
                } else {
                    if (![updateIndexes containsObject:[NSNumber numberWithInteger:newIndex]]) {
                        [changeObjects addObject:[LYRUIDataSourceChange changeObjectWithType:LYRUIDataSourceChangeTypeUpdate newIndex:newIndex oldIndex:0]];
                        [updateIndexes addObject:[NSNumber numberWithInteger:newIndex]];
                    }
                }
            }
                break;
                
            case LYRObjectChangeTypeDelete:
                [changeObjects addObject:[LYRUIDataSourceChange changeObjectWithType:LYRUIDataSourceChangeTypeDelete newIndex:newIndex oldIndex:0]];
                break;
                
            default:
                break;
        }
    }
    self.identifiers = self.tempIdentifiers;
    completion(changeObjects);
}

- (void)dispatchChanges:(NSArray *)changes
{
    dispatch_async(dispatch_get_main_queue(), ^{
        NSLog(@"CHANGES FUCKING ENDED");
        [self.delegate observer:self updateWithChanges:changes];
        [self.delegate observer:self didChangeContent:TRUE];
    });
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

@end