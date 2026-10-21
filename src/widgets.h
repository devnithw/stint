// Building blocks shared by the views: the card, the end-of-block blink, buttons, hit zones.
#pragma once
#import "app.h"

void AddZone(int id, CGFloat x, CGFloat y, CGFloat w, CGFloat h);  // clickable area for a Z_* id
void DrawCard(CGFloat w, CGFloat h, CGFloat r);
void DrawBlink(CGFloat w, CGFloat h, CGFloat r);
void CircleButton(int id, CGFloat cx, CGFloat cy, CGFloat r, int icon, CGFloat iconSize);
void IconButton(int id, int icon, CGFloat cx, CGFloat cy);
