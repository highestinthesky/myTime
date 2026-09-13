Run each step against scripts/build.sh --dev unless noted.

## Run 1

1. **Install:** the menu bar shows `DEV ◆ 0`. `launchctl print gui/$(id -u)/local.mytime.agent` shows the job running.
2. **Keep-alive:** force quit myTime in Activity Monitor → it's back within ~5 s.
3. **Startup sweep:** with Discord open, `launchctl kickstart -k gui/$(id -u)/local.mytime.agent` → Discord quits with no gate.
4. **Gate, no tokens:** open Discord → it's hidden, the gate appears, options stay locked for 5 s, and "No tokens yet…" shows.
5. **Never mind:** Discord quits.
6. **Quick look:**
   - Press "+1 token" twice, open Discord, wait 5 s, buy 2.
   - Discord appears, and the pill and menu bar count down from 1:00 (after launch grace).
   - At ≤ 10 s the pill turns warm and offers +30 s.
   - At 0, Discord quits within ~1 s.
7. **Idle cost:** with nothing unlocked and the panel closed, watch Activity Monitor → Energy for 2 minutes → myTime shows 0.0 CPU and near-zero idle wake-ups.
