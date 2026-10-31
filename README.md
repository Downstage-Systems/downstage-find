# Downstage Find

A Mac app that finds the Downstage devices on your network and opens their apps: Downstage One, Downstage View, Cue Relay and Cue lights.

- It asks the network over Bonjour (`_downstage._tcp`), so there are no addresses to know.
- On a network that hides devices from each other, add one by its address, or run a scan. A scan only runs when you ask for it.

Build it with `macapp/build.sh` (Apple Silicon, needs Xcode). It writes `dist/`.
