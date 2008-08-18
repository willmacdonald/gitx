//
//  PBGitRepository.m
//  GitTest
//
//  Created by Pieter de Bie on 13-06-08.
//  Copyright 2008 __MyCompanyName__. All rights reserved.
//

#import "PBGitRepository.h"
#import "PBGitCommit.h"
#import "PBDetailController.h"

#import "NSFileHandleExt.h"
#import "PBEasyPipe.h"

NSString* PBGitRepositoryErrorDomain = @"GitXErrorDomain";

@implementation PBGitRepository

@synthesize revisionList;
static NSString* gitPath;

+ (void) initialize
{
	// Try to find the path of the Git binary
	char* path = getenv("GIT_PATH");
	if (path != nil) {
		gitPath = [NSString stringWithCString:path];
		return;
	}
	
	// No explicit path. Try it with "which"
	gitPath = [PBEasyPipe outputForCommand:@"/usr/bin/which" withArgs:[NSArray arrayWithObject:@"git"]];
	if (gitPath.length > 0)
		return;
	
	// Still no path. Let's try some default locations.
	NSArray* locations = [NSArray arrayWithObjects:@"/opt/local/bin/git", @"/sw/bin/git", @"/opt/git/bin/git", nil];
	for (NSString* location in locations) {
		if ([[NSFileManager defaultManager] fileExistsAtPath:location]) {
			gitPath = location;
			return;
		}
	}
	
	NSLog(@"Could not find a git binary!");
}

- (BOOL)readFromData:(NSData *)data ofType:(NSString *)typeName error:(NSError **)outError
{
	if (outError) {
		*outError = [NSError errorWithDomain:PBGitRepositoryErrorDomain
                                      code:0
                                  userInfo:[NSDictionary dictionaryWithObject:@"Reading files is not supported." forKey:NSLocalizedFailureReasonErrorKey]];
	}
	return NO;
}

+ (NSURL*)gitDirForURL:(NSURL*)repositoryURL;
{
	NSString* repositoryPath = [repositoryURL path];
	NSURL* gitDirURL         = nil;

	if ([repositoryPath hasSuffix:@".git"]) {
		gitDirURL = [NSURL fileURLWithPath:repositoryPath];
	} else {
		// Use rev-parse to find the .git dir for the repository being opened
		NSString* newPath = [PBEasyPipe outputForCommand:gitPath withArgs:[NSArray arrayWithObjects:@"rev-parse", @"--git-dir", nil] inDir:repositoryPath];
		if ([newPath isEqualToString:@".git"]) {
			gitDirURL = [NSURL fileURLWithPath:[repositoryPath stringByAppendingPathComponent:@".git"]];
		} else if ([newPath length] > 0) {
			gitDirURL = [NSURL fileURLWithPath:newPath];
		}
	}

	return gitDirURL;
}

- (BOOL)readFromFileWrapper:(NSFileWrapper *)fileWrapper ofType:(NSString *)typeName error:(NSError **)outError
{
	BOOL success = NO;

	if (![fileWrapper isDirectory]) {
		if (outError) {
			NSDictionary* userInfo = [NSDictionary dictionaryWithObject:[NSString stringWithFormat:@"Reading files is not supported.", [fileWrapper filename]]
                                                              forKey:NSLocalizedRecoverySuggestionErrorKey];
			*outError = [NSError errorWithDomain:PBGitRepositoryErrorDomain code:0 userInfo:userInfo];
		}
	} else {
		NSURL* gitDirURL = [PBGitRepository gitDirForURL:[self fileURL]];
		if (gitDirURL) {
			[self setFileURL:gitDirURL];
			success = YES;
		} else if (outError) {
			NSDictionary* userInfo = [NSDictionary dictionaryWithObject:[NSString stringWithFormat:@"%@ does not appear to be a git repository.", [fileWrapper filename]]
                                                              forKey:NSLocalizedRecoverySuggestionErrorKey];
			*outError = [NSError errorWithDomain:PBGitRepositoryErrorDomain code:0 userInfo:userInfo];
		}

		if (success) {
			revisionList = [[PBGitRevList alloc] initWithRepository:self andRevListParameters:[NSArray array]];
		}
	}

	return success;
}

// The fileURL the document keeps is to the .git dir, but that’s pretty
// useless for display in the window title bar, so we show the directory above
- (NSString*)displayName
{
	NSString* displayName = self.fileURL.path.lastPathComponent;
	if ([displayName isEqualToString:@".git"])
		displayName = [self.fileURL.path stringByDeletingLastPathComponent].lastPathComponent;
	return displayName;
}

// Overridden to create our custom window controller
- (void)makeWindowControllers
{
	PBDetailController* controller = [[PBDetailController alloc] initWithRepository:self];
	[self addWindowController:controller];
	[controller release];
}

+ (PBGitRepository*) repositoryWithPath:(NSString*) path
{
	PBGitRepository* repo = [[PBGitRepository alloc] initWithPath: path];
	return repo;
}

- (PBGitRepository*) initWithPath: (NSString*) p
{
	if ([p hasSuffix:@".git"])
		[self setFileURL:[NSURL fileURLWithPath:p]];
	else {
		NSString* newPath = [PBEasyPipe outputForCommand:gitPath withArgs:[NSArray arrayWithObjects:@"rev-parse", @"--git-dir", nil] inDir:p];
		if ([newPath isEqualToString:@".git"])
			[self setFileURL:[NSURL fileURLWithPath:[p stringByAppendingPathComponent:@".git"]]];
		else
			[self setFileURL:[NSURL fileURLWithPath:newPath]];
	}

	NSLog(@"Git path is: %@", self.fileURL);
	revisionList = [[PBGitRevList alloc] initWithRepository:self andRevListParameters:[NSArray array]];
	return self;
}


- (NSFileHandle*) handleForArguments:(NSArray *)args
{
	NSString* gitDirArg = [@"--git-dir=" stringByAppendingString:self.fileURL.path];
	NSMutableArray* arguments =  [NSMutableArray arrayWithObject: gitDirArg];
	[arguments addObjectsFromArray: args];
	return [PBEasyPipe handleForCommand:gitPath withArgs:arguments];
}

- (NSFileHandle*) handleForCommand:(NSString *)cmd
{
	NSArray* arguments = [cmd componentsSeparatedByString:@" "];
	return [self handleForArguments:arguments];
}

@end
