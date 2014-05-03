/*
 Copyright (c) 2002-2006, Kurt Revis.  All rights reserved.
 
 Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:
 
 * Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
 * Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
 * Neither the name of Kurt Revis, nor Snoize, nor the names of other contributors may be used to endorse or promote products derived from this software without specific prior written permission.
 
 THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

#import "SSEFindMissingController.h"

#import <SnoizeMIDI/SnoizeMIDI.h>
#import "SSEMainWindowController.h"
#import "SSELibrary.h"
#import "SSELibraryEntry.h"


@interface SSEFindMissingController (Private)

- (void)findNextMissingFile;
- (void)missingFileAlertDidEnd:(NSWindow *)sheet returnCode:(int)returnCode contextInfo:(void *)contextInfo;

- (void)runOpenSheetForMissingFile;
- (void)findMissingFileOpenPanelDidEnd:(NSOpenPanel *)openPanel returnCode:(int)returnCode contextInfo:(void *)contextInfo;

@end


@implementation SSEFindMissingController

- (id)initWithWindowController:(SSEMainWindowController *)mainWindowController library:(SSELibrary *)library;
{
    if (!(self = [super init]))
        return nil;

    nonretainedMainWindowController = mainWindowController;
    nonretainedLibrary = library;

    return self;
}

- (void)dealloc;
{
    [entriesWithMissingFiles release];
    entriesWithMissingFiles = nil;
    
    [super dealloc];
}

//
// API for main window controller
//

- (void)findMissingFilesForEntries:(NSArray *)entries andPerformSelectorOnWindowController:(SEL)selector;
{
    // Ask the user to find each missing file.
    // If we go through them all successfully, perform the selector on the main window controller.
    // If we cancel at any point of the process, don't do anything.

    SMAssert(entriesWithMissingFiles == nil);
    entriesWithMissingFiles = [[NSMutableArray alloc] initWithArray:entries];
    finishingSelector = selector;

    [self findNextMissingFile];
}

@end


@implementation SSEFindMissingController (Private)

- (void)findNextMissingFile;
{
    if ([entriesWithMissingFiles count] > 0) {
        SSELibraryEntry *entry;
        NSString *title, *message;
        NSString *yes, *cancel;

        entry = [entriesWithMissingFiles objectAtIndex:0];

        title = NSLocalizedStringFromTableInBundle(@"Missing File", @"SysExLibrarian", SMBundleForObject(self), "title of alert for missing file");
        message = NSLocalizedStringFromTableInBundle(@"The file for the item \"%@\" could not be found. Would you like to locate it?", @"SysExLibrarian", SMBundleForObject(self), "format of message for missing file");
        yes = NSLocalizedStringFromTableInBundle(@"Yes", @"SysExLibrarian", SMBundleForObject(self), "Yes");
        cancel = NSLocalizedStringFromTableInBundle(@"Cancel", @"SysExLibrarian", SMBundleForObject(self), "Cancel");
        
        NSBeginAlertSheet(title, yes, cancel, nil, [nonretainedMainWindowController window], self, @selector(missingFileAlertDidEnd:returnCode:contextInfo:), NULL, NULL, message, [entry name]);
    } else {
        [nonretainedMainWindowController performSelector:finishingSelector];
    }
}

- (void)missingFileAlertDidEnd:(NSWindow *)sheet returnCode:(int)returnCode contextInfo:(void *)contextInfo;
{
    if (returnCode == NSAlertDefaultReturn) {
        // Get this sheet out of the way before we open another one
        [sheet orderOut:nil];

        // Try to locate the file
        [self runOpenSheetForMissingFile];
    } else {
        // Cancel the whole process
        [entriesWithMissingFiles release];
        entriesWithMissingFiles = nil;
    }
}

- (void)runOpenSheetForMissingFile;
{
    NSOpenPanel *openPanel;

    openPanel = [NSOpenPanel openPanel];
    
    if ([openPanel respondsToSelector:@selector(beginSheetModalForWindow:completionHandler:)]) {
        [openPanel setAllowedFileTypes:[nonretainedLibrary allowedFileTypes]];
        [openPanel beginSheetModalForWindow:[nonretainedMainWindowController window] completionHandler:^(NSInteger result) {
            [self findMissingFileOpenPanelDidEnd:openPanel returnCode:result contextInfo:NULL];
        }];
    } else {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    
        [openPanel beginSheetForDirectory:nil file:nil types:[nonretainedLibrary allowedFileTypes] modalForWindow:[nonretainedMainWindowController window] modalDelegate:self didEndSelector:@selector(findMissingFileOpenPanelDidEnd:returnCode:contextInfo:) contextInfo:NULL];
        
#pragma clang diagnostic pop
    }
}

- (void)findMissingFileOpenPanelDidEnd:(NSOpenPanel *)openPanel returnCode:(int)returnCode contextInfo:(void *)contextInfo;
{
    BOOL cancelled = NO;

    if (returnCode != NSOKButton || [[openPanel URLs] count] == 0) {
        cancelled = YES;
    } else {
        SSELibraryEntry *entry;
        NSString *filePath;
        NSArray *matchingEntries;

        SMAssert([entriesWithMissingFiles count] > 0);
        entry = [entriesWithMissingFiles objectAtIndex:0];

        filePath = [[[openPanel URLs] objectAtIndex:0] path];

        // Is this file in use by any entries?  (It might be in use by *this* entry if the file has gotten put in place again!)
        matchingEntries = [nonretainedLibrary findEntriesForFiles:[NSArray arrayWithObject:filePath] returningNonMatchingFiles:NULL];
        if ([matchingEntries count] > 0 && [matchingEntries indexOfObject:entry] == NSNotFound) {
            NSString *title, *message, *ok, *cancel;
            int returnCode2;

            title = NSLocalizedStringFromTableInBundle(@"In Use", @"SysExLibrarian", SMBundleForObject(self), "title of alert for file already in library");
            message = NSLocalizedStringFromTableInBundle(@"That file is already in the library. Please choose another one.", @"SysExLibrarian", SMBundleForObject(self), "message for file already in library");
            ok = NSLocalizedStringFromTableInBundle(@"OK", @"SysExLibrarian", SMBundleForObject(self), "OK");
            cancel = NSLocalizedStringFromTableInBundle(@"Cancel", @"SysExLibrarian", SMBundleForObject(self), "Cancel");
            
            returnCode2 = NSRunAlertPanel(title, @"%@", ok, cancel, nil, message);
            [openPanel orderOut:nil];
            if (returnCode2 == NSAlertDefaultReturn) {
                // Run the open sheet again
                [self runOpenSheetForMissingFile];
            } else {
                // Cancel out of the whole process
                cancelled = YES;
            }

        } else {
            [openPanel orderOut:nil];

            [entry setPath:filePath];
            [entry setNameFromFile];

            [entriesWithMissingFiles removeObjectAtIndex:0];

            // Go on to the next file (if any)
            [self findNextMissingFile];
        }
    }

    if (cancelled) {
        // Cancel the whole process
        [entriesWithMissingFiles release];
        entriesWithMissingFiles = nil;
    }
}

@end
