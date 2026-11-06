<div align="center">

<p align="center">
  <img src="docs/app-icon.png" width="140" height="140" alt="Pulse icon">
  <br>
  <img src="docs/ui/wordmark.svg" width="640" alt="Pulse. Your home server, one glance away.">
</p>

A native menu bar app for your Mac that watches your home server:<br>
vitals, containers and alerts in one Liquid Glass popover.

<br>

<a href="https://github.com/adrbn/pulse/releases/latest/download/Pulse.dmg"><img src="docs/ui/btn-download.svg" height="44" alt="Download for Mac"></a>&nbsp;&nbsp;
<a href="https://ko-fi.com/adrbn"><img src="docs/ui/btn-kofi.svg" height="44" alt="Buy me a coffee on Ko-fi"></a>

<a href="#four-styles"><img src="docs/ui/btn-styles.svg" height="44" alt="Four styles"></a>&nbsp;&nbsp;
<a href="#connect-a-server"><img src="docs/ui/btn-setup.svg" height="44" alt="Connect a server"></a>

<br>

<a href="https://github.com/adrbn/pulse/releases/latest"><img src="docs/ui/pills.svg" height="30" alt="v1.0.6, macOS 26+, Beszel, Proxmox, Docker, notarized, no account, MIT"></a>

<br>

<img src="docs/shots/hero.png" width="780" alt="The Pulse popover in light and dark: rings for CPU, memory and disk, a halo of containers, temperature, load and network tiles, and a stopped container with a Start button">

<sub>Every screenshot uses built-in mock data.</sub>

<br><br>

<img src="docs/ui/h-why.svg" width="720" alt="Know before it breaks">

Your dashboard lives in a browser tab you never open.<br>
**Pulse lives in the menu bar.** One ring says all is well.<br>
When a container dies, a notification shows up with a **Start** button.

<br>

<img src="docs/ui/features.svg" width="780" alt="One look: vitals as rings. One click: restart a dead container. Quiet alerts. Widgets. Truly native. Private.">

<br><br>

<a id="four-styles"></a>
<img src="docs/ui/h-styles.svg" width="720" alt="Four ways to read it">

<img src="docs/shots/styles-dark.png" width="100%" alt="Halo, Rings, Memory and Live styles in dark mode">

**Halo** circles the vitals with your containers &nbsp;·&nbsp; **Rings** puts vitals first<br>
**Memory** replays the last 24 hours &nbsp;·&nbsp; **Live** shows every Compose stack

<img src="docs/shots/styles-light.png" width="100%" alt="Halo, Rings, Memory and Live styles in light mode">

<br><br>

<img src="docs/ui/h-states.svg" width="720" alt="Colour first, numbers second">

<img src="docs/shots/states.png" width="100%" alt="The same popover healthy, in warning with orange rings, and offline in grey">

<br><br>

<img src="docs/ui/h-widgets.svg" width="720" alt="On your desktop, too">

<img src="docs/shots/widgets-dark.png" width="100%" alt="Small and medium widgets in dark mode">
<img src="docs/shots/widgets-light.png" width="100%" alt="Small and medium widgets in light mode">

<img src="docs/shots/menubar.png" width="640" alt="A dark menu bar with the Halo, Rings and Live icons, each healthy, warning and offline">

<br><br>

<a id="install"></a>
<img src="docs/ui/h-install.svg" width="720" alt="Up in a minute">

</div>

1. **[Download Pulse.dmg](https://github.com/adrbn/pulse/releases/latest/download/Pulse.dmg)**, signed and notarized by Apple.
2. Drag **Pulse** into **Applications** and open it. It lives in the menu bar, not the Dock.
3. Right click the icon, choose **Settings…**, and connect your server.

Requires macOS 26 or later. Left click the icon for the popover; right click for **Refresh** ⌘R, **Settings…** ⌘, and **Quit** ⌘Q.

<div align="center">

<br>

<a id="connect-a-server"></a>
<img src="docs/ui/h-connect.svg" width="720" alt="Plug in your server">

</div>

| | You enter | You get |
|---|---|---|
| **[Beszel](https://beszel.dev)** · recommended | Hub URL, email, password, system name | CPU, memory, disk, temperature, load, network, running containers |
| **Proxmox VE** | API URL, node, API token with `Sys.Audit` | The same, without temperature |
| **Docker** · optional, with either | `http://your-server:8772` | Stopped containers, exit codes, the **Start** button |

Beszel doesn't see stopped containers, and **Start** needs the Docker Engine API. The socket proxy in
[`deploy/docker-socket-proxy.yml`](deploy/docker-socket-proxy.yml) is locked down to list, inspect and start, from one IP.

<details>
<summary><b>When does Pulse turn orange or red?</b></summary>

<br>

| State | When |
|---|---|
| **Offline** | No answer for 60 s. Alert after 3 minutes. |
| **Warning** | An unhealthy container, CPU above 90 % for 5 minutes, memory above 90 %, disk above 85 %, temperature above 85 °C. Stopped containers too, if you turn that on. |
| **Critical rings** | CPU 98 %, memory 95 %, disk 95 %. |

</details>

<details>
<summary><b>Privacy</b></summary>

<br>

Pulse talks to the servers you enter and nowhere else. Passwords and tokens stay in the macOS Keychain.
No account, no analytics, no update server.

</details>

<details>
<summary><b>Build from source</b></summary>

<br>

```bash
brew install xcodegen
git clone https://github.com/adrbn/pulse && cd pulse
xcodegen generate
xcodebuild -project Pulse.xcodeproj -scheme Pulse -configuration Release -derivedDataPath build/dd build
```

Set `DEVELOPMENT_TEAM` in `project.yml` and the App Group in the entitlements to your own team.
Tests: `cd PulseKit && swift test`. Render every style, state and widget as PNG with
`Pulse.app/Contents/MacOS/Pulse --render-snapshots ~/Library/Containers/dev.adrbn.pulse/Data/tmp/snaps`.

</details>

<div align="center">

<br>

<img src="docs/ui/h-support.svg" width="720" alt="Free, and staying that way">

If Pulse saves you a trip to the dashboard, a coffee keeps it going.

<a href="https://ko-fi.com/adrbn"><img src="docs/ui/btn-kofi.svg" height="44" alt="Buy me a coffee on Ko-fi"></a>

<br><br>

<sub>MIT License · © Adrien Robino</sub>

</div>
