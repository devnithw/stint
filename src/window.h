// The floating panel and its canvas: view switching, placement on screen, mouse and scroll input.
#pragma once
#import "app.h"

@interface StintPanel : NSPanel
@end
@interface StintView : NSView
@end

NSRect ClampToWork(NSRect f);  // keeps the card on the screen it mostly sits on
void Render();                 // synchronous, so hit zones are current on return
void SetView(View v);
void OpenSetup();
void ApplyTopmost();
void ShowWidget();
void HideWidget();
void Quit();
