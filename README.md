# Weather65

A retro TV-weather-channel display for the MEGA65. It fetches live forecasts and a radar loop over the
machine's own Ethernet port, with no PC or proxy in between. Inspired by
[WeatherStar 4000+](https://github.com/netbymatt/ws4kp) (MIT). All code and art here are new; its fonts,
graphics and music are not used.

## Build and run

    build.bat              writes target\weather65.d81
    run.bat                builds and starts Xemu (stops at "NO WEATHER DATA": Xemu has no network)
    build.bat mock DIR     replay build for Xemu: captured HTTP responses replace the network

Copy `target\weather65.d81` to the SD card and mount it; `AUTOBOOT.C65` starts the app. Plug in Ethernet, on a
network with DHCP. On first start, type a city name or ZIP code and pick from the list. The choice is saved
to the disk as `WXCONFIG`, so **the D81 must be writable**.

## Bundled tools

The repo root includes two Windows command-line tools that `build.bat` runs:

| Tool | Used for | Project | Source |
|---|---|---|---|
| `64tass.exe` (v1.60.3243) | Assembler | [64tass](https://tass64.sourceforge.net/) | [SourceForge](https://sourceforge.net/projects/tass64/) |
| `c1541.exe` (VICE 3.9) | Writes the D81 | [VICE](https://vice-emu.sourceforge.io/) | [GitHub mirror](https://github.com/VICE-Team/svn-mirror) |

These are separate projects by their own authors, distributed under the GNU GPL, and included
unmodified so that the project builds without installing anything else. Their licences apply to them,
not to this project.

## Controls

| Key | Action |
|---|---|
| SPACE / cursor right | Next screen |
| Cursor left | Previous screen |
| L | Change location |
| U | Switch between F + mph and C + km/h |
| R | Refresh now (otherwise every 10 minutes) |
| N | Network details (any key returns) |

Screens rotate every 12 seconds: current conditions, next 12 hours, 7 day forecast, national cities,
almanac, local radar.

## Data sources

Everything is plain HTTP, because mega-ip has no TLS. That rules out `api.weather.gov`, which only answers HTTPS.

| Data | Source | Notes |
|---|---|---|
| Forecasts, cities | [Open-Meteo](https://open-meteo.com) | Worldwide. Free for non-commercial use; attribution is in the ticker |
| Location search | Open-Meteo geocoding | |
| Radar | [Iowa Environmental Mesonet](https://mesonet.agron.iastate.edu) NEXRAD WMS | Lower 48 US states only; elsewhere the radar screen is skipped |
| Map outlines | [Natural Earth](https://www.naturalearthdata.com) | Public domain, baked into `src/assets/usmap.png` |

If one of these servers stops offering plain HTTP, that part fails with a message in the ticker. The fix
would then be a small HTTP relay on the local network, plus a host change in `net.asm`.

## Architecture

| File | What |
|---|---|
| `src/mega-ip/` | The TCP/IP stack, a copy of `mega-ip/src` with one fix: `ETH_RCV` rotates the receive buffers before reading |
| `src/net.asm` | MAP trampoline into the stack, DHCP, DNS, HTTP/1.0 client, response parser (headers, chunked), replay mode |
| `src/weather.asm` | Forward-scanning JSON reader, Open-Meteo requests, tables, dates, moon phase, weather codes |
| `src/inflate.asm` | PNG reader and DEFLATE decoder, verified with zlib's Adler-32 |
| `src/radar.asm` | View calculation, WMS requests, compositing, frames |
| `src/ui.asm` | Text, big text, ticker, every screen, the location picker |
| `src/main.asm` | Boot, main loop, config file |
| `src/lib/` | Project template library |

Memory:

| Where | What |
|---|---|
| `$0800`, `$1000`, `$C800` | Screen RAMs |
| `$1800`, `$1900`, `$1A00` | kfile trampoline, mega-ip trampoline, receive block |
| `$2001`-about `$9A00` | Program and tables |
| `$12000` | Config file staging |
| `$20000`, `$30000` | Framebuffers (the ROM area, made writable) |
| `$42000-$47FFF` | mega-ip code |
| `$50000-$515FF` | mega-ip receive ring |
| `$8000000` / `$8060000` | Map / icons |
| `$8100000` / `$8110000` | Background / location map |
| `$8200000` | Copy of the ROM area, so the KERNAL can save the config |
| `$8300000` / `$8400000` | HTTP body / decoded radar image |
| `$8500000` | 6 finished radar frames |

Asset formats are in `src/assets/README.md`. MEGA65 findings are in `docs/MEGA65_NOTES.md`, section 13.

## Testing status

Xemu has no network, so the Ethernet path can only be proved on real hardware; `TODO.md` lists what to look
at first. The replay build runs everything above the driver on real captured server responses, and writes its
requests to attic so they can be sent to the live servers byte for byte.

## Known differences from WeatherStar 4000+

No severe weather alerts or SPC outlooks (the NWS API needs HTTPS), no regional map, no forecast-model radar,
no music. Radar has no county lines or city labels. The clock is set from the server's `Date:` header at each
refresh and counted by frames in between.
