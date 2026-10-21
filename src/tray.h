// The menu bar item: icon, tooltip, and the menu shared with the right-click popup.
#pragma once
#import "app.h"

void UpdateTray();
NSImage* TrayImage();
void FillMenu(NSMenu* m, id target);
