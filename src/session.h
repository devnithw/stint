// Session logic: the plan of blocks, the clock that advances it, and the timers that drive it.
#pragma once
#import "app.h"

std::vector<Block> BuildPlan(const Cfg& c);
bool Complete();                 // every block is done
Block* Cur();                    // current block, or nullptr when complete
bool Over();                     // current block has run past its time
long long FocusedMs();
long long ExtraMs();
int RoundsDone();

void ResetSession(bool run);
void SetRunning(bool on);
void Advance();                  // finish the current block and move to the next
void Tick();                     // called every 0.2 s: advances the clock
void UpdateActivity();           // keeps App Nap off while running

NSTimer* Every(double secs, void (^fn)(void));  // repeating main-run-loop timer
void Kill(NSTimer* __strong& t);
void OpenFocusSettings();
