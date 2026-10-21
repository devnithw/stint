// Settings, stored with NSUserDefaults (~/Library/Preferences/<bundle id>.plist).
#pragma once
#import "app.h"

int PrefInt(NSString* k, int def);
void LoadSettings();
void SaveSettings();  // also saves the window position
