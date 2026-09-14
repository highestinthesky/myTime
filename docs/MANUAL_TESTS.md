Run each step against scripts/build.sh --dev unless noted.

## Run 1

1. **Install:** the menu bar shows `DEV ◆ 0`. `launchctl print gui/$(id -u)/local.mytime.agent` shows the job running.
2. **Keep-alive:** force quit myTime in Activity Monitor → it's back within ~5 s.
3. **Startup sweep:** with Discord open, `launchctl kickstart -k gui/$(id -u)/local.mytime.agent` → Discord quits with no gate.
4. **Gate, no tokens:** open Discord → it quits with no window flashing, the gate appears, options stay locked for 5 s, and "No tokens yet…" shows. Opening Discord again while the gate is up quits it quietly without a second gate. The gate can be dragged.
5. **Never mind:** Discord quits.
6. **Quick look:**
   - Press "+1 token" twice, open Discord, wait 5 s, buy 2.
   - Discord relaunches, and the pill and menu bar count down from 1:00 right away.
   - At ≤ 10 s (not later) the pill turns warm and offers +30 s. The pill can be dragged and reopens where it was left.
   - At 0, Discord quits within ~1 s.
7. **Idle cost:** with nothing unlocked and the panel closed, watch Activity Monitor → Energy for 2 minutes → myTime shows 0.0 CPU and near-zero idle wake-ups.

## Run 2

8. **Earn:** Start Focus and keep using the Mac for ~20 s → a token appears within ~5 s of crossing 15 s, and the menu bar ring fills.
9. **Idle:**
   - During focus, don't touch anything for 30 s → the pause icon appears.
   - Touch the mouse → within ~5 s the claim dot appears, and the panel shows the claim row.
   - Hold 2 s → progress increases and the dot clears.
10. **Lock:** during focus, lock the screen for 30 s, then unlock → the claim row offers ~30 s.
11. **Focus card:** open Discord during focus → the focus card appears. **Back to work** quits Discord, and "Backed off" +1.
12. **New day:** press "New day" → tokens and progress go to 0, and history records the reset.
13. **Shutdown:** Start Focus, restart the Mac → after login, focus is off and no time was credited for the restart.
14. **Short sleep:** during focus, close the lid for 1 minute and reopen → focus is still on, and no away time is offered for the sleep.
15. **Focus card:** during focus, open Discord → Discord quits with no window flashing and the "You're focusing" card appears. **End focus…** swaps to the gate with a fresh 5 s pause, and "Backed off" does **not** increase.

## Run 3

16. **Reply mode:**
    - Typing in the gate's text field works while another app is in front.
    - A note under 8 characters keeps Open disabled, with "Write at least 8 characters".
    - A valid note → Discord relaunches and the pill shows the note.
    - The 4th reply today is refused ("No replies left today").
17. **Booking:**
    - From the gate, "Book a session…" closes the gate and opens the Booking window in front. The day, start, and duration menus list valid choices only.
    - Book a 1-minute session starting ~1 minute ahead. The panel lists it under Sessions with **Cancel**, and the gate shows "Next session: …".
    - At the start, Discord opens freely with no gate and no pill, and the menu bar shows the hourglass.
    - 30 s before the end, the heads-up shows for 8 s (below the pill if one is showing).
    - At the end, Discord quits.
    - Book another and never open Discord → the allowance is fully refunded.
18. **Emergency:** from the gate, enter a 15+ character reason, wait 10 s (Cancel during the wait keeps the pass), open → 1 minute of access with an "Emergency" pill. The gate then shows "Emergency access used · resets Monday".
