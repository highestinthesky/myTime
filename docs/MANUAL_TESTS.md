# Manual tests

Checks that need a real Mac and an installed build. Steps are numbered across runs; add new ones at the end. Results are recorded in `IMPLEMENTATION_NOTES.md` (only steps 1–7 have recorded results so far).

Run each step against scripts/build.sh --dev unless noted.

## Run 1

1. **Install:** the menu bar shows `◆ 0` and the panel title says "myTime · DEV". `launchctl print gui/$(id -u)/local.mytime.agent` shows the job running.
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
    - At the start, the "Your session has started" reminder shows for 8 s even with Discord closed; **Open Discord** opens it.
    - Discord opens freely with no gate and no pill, and the menu bar shows the hourglass.
    - 30 s before the end, the heads-up shows for 8 s (below the pill if one is showing).
    - At the end, Discord quits.
    - Book another and never open Discord → the allowance is fully refunded.
18. **Emergency:** from the gate, enter a 15+ character reason, wait 10 s (Cancel during the wait keeps the pass), open → 1 minute of access with an "Emergency" pill. The gate then shows "Emergency access used · resets Monday".
19. **Quit:**
    - `/Applications/myTime.app` exists and shows in Finder's Applications folder.
    - Panel → **Quit myTime…**: Start stays disabled until 15 characters; Cancel or closing the window during the 10 s wait keeps myTime running.
    - After the wait, **Quit myTime** → the menu bar item disappears, Discord opens with no gate, and myTime is not back after 30 s or after logging out and in.
    - Open myTime from Applications → the menu bar item returns with the same token count, and Discord is gated again.

## Run 4

20. **Loosening:** raise "Session time per week" → the "Settings updated" alert lists it under "Applies <time>" about a minute ahead, the panel shows "1 pending", the Pending tab lists it, and it applies. Lower it → "Applied now". Opening myTime from Applications while it runs opens Settings.
21. **Day start:** change "Day starts at" → scheduled, never immediate.
22. **Blocked apps:** add TextEdit → opening it shows the gate. Remove TextEdit → pending, still blocked until applied.
23. **Clock tamper:** set the system time +2 h → no tokens gained, pending changes don't apply early, and Settings shows the clock-change note.
24. **File tamper:** edit one character in `state-dev.json`, then kickstart the agent → tokens are 0 and the tamper banner shows.
25. **Uninstall:** schedule uninstall → after ~1 minute myTime leaves the menu bar and is not relaunched, and `/Applications/myTime.app` is in the Trash.

Then re-run steps 1–7 against a release build (`scripts/build.sh`).

## Run 5 — Unlock

These checks are for the reviewer; no install or launch-agent commands were run during implementation. From Run 5 on, steps 6 and 16 are historical. Step 4 now shows the Unlock card's "Unlock needs 1 more token for 10 s." (DEV), its next-token line, and one **Start Focus** button.

26. **Unlock gate:** press "+1 token" 6 times, open Discord. The lengths 10 s, 20 s, 50 s, 100 s show their prices but stay disabled for 5 s; nothing is preselected and the button reads "Choose a length". Pick 20 s → "Unlock 20 s · 2 tokens". Buy → Discord relaunches, no pill shows, and the menu bar shows the hourglass and "20 s".
27. **Warning:** type in Discord during an Unlock. At 5 s left, "Discord closes in 0:05" appears top-right and typing still goes to Discord. **End now** quits Discord at once.
28. **Streak:** reopen Discord within 30 s of the end → the pause is 10 s, prices are doubled, and the card header reads "2× — resets at …". Choose a length and keep the gate open past that time → the prices and the Unlock button drop to 1× without closing the gate.
29. **Panel:** during an Unlock the panel shows "Unlock · 0:15 left", **End Unlock**, and "Next Unlock: 2× until …". **End Unlock** quits Discord.
30. **Restart:** during an Unlock, `launchctl kickstart -k gui/$(id -u)/local.mytime.agent` → the same end time; a warning already shown doesn't show again; at the end Discord quits.

31. **Migration:** with a `state-dev.json` written by 0.1.0 (Quick look on), install the DEV build → no tamper banner, history unchanged (tokens too if the file was saved today; otherwise the new day clears them as usual), the migration notice shows once in the panel, Discord shows Unlock on in Settings. **Dismiss** removes it for good.
32. **Settings:** Blocked Apps shows "Unlock" and "Sessions". Turning Unlock on shows the loosening alert. With an Unlock running and TextEdit blocked with Unlock, turning Unlock off for TextEdit quits TextEdit at once; Discord stays open until the end.

33. **Icon:** after the next reviewer-approved install, `/Applications/myTime.app` shows the new icon in Finder and Get Info (if Finder shows a blank icon, `touch /Applications/myTime.app`). This was not run during implementation.
