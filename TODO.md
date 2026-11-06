# TODO

## If it fails on real hardware

DHCP, ARP, DNS, TCP and HTTP all work on hardware, at a good speed (2026-11-06). Expected: "STARTING ETHERNET" for about 4 s,
"ASKING FOR AN ADDRESS", then the location prompt.

| You see | Likely cause | Look at |
|---|---|---|
| `STACK NOT LOADED` | The MAP trampoline isn't reaching bank 4 | `net_selftest`, `net_install` |
| Hang at `STARTING ETHERNET` | Stack init under this MAP | `MIP_INIT` |
| `DHCP TIMEOUT` | Cable or link, or stack state after the takeover | Does `ansi-term` get an address on this network? |
| `DNS LOOKUP FAILED` | Neither the DHCP DNS server nor 8.8.8.8 answered (the N screen shows 8.8.8.8 after the fallback) | N screen; a capture |
| `CANNOT CONNECT` | Routing, or a firewall on port 80 | N screen: gateway |
| `NO DATA FROM SERVER` | Connected, then nothing for 20 s | `http_once` receive loop |
| `SERVER ERROR` | The server refused the request | N screen: last code |
| `RADAR CHECKSUM BAD` | Bytes corrupted or lost in TCP receive | The stack's receive path |
| Dark screen and a hang after picking a location | KERNAL save after the takeover (`cfg_save`) | Does `WXCONFIG` appear on the disk? |

Also check on hardware:

- [ ] Radar loop smoothness (each step is 2 DMAs of 64,000 bytes from attic; Xemu doesn't model attic timing)
- [ ] How long a full refresh takes (9 requests; my estimate is 5-15 s)
- [ ] A day of running: DHCP lease renewal, repeated connections

## Ideas

- [ ] Static IP setup for networks without DHCP (the stack has the setters; it needs a screen)
- [ ] Severe weather alerts, from an HTTP source or a small local HTTPS relay
- [ ] City labels and county lines on the radar map
- [ ] Wider and closer radar zoom levels
- [ ] Background music
- [ ] Move `inflate.asm` to the template library (decouple it from `net_err` and the radar buffers)
