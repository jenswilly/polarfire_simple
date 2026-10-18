# Tools: Libero license server

Libero SoC on Linux uses a **FlexLM floating license**. Even on a single machine, a local license server (`lmgrd` plus vendor daemons) must be running before Libero starts. The scripts in this directory handle starting and stopping it.

| Script | What it does |
|---|---|
| `start_libero.sh` | Starts the license server if it isn't up yet, waits until `actlmgrd` reports UP, sets the license environment variables and then `exec`s Libero. Arguments are passed through to Libero. |
| `stop_licenser_server.sh` | Stops the license server: first `lmutil lmdown`, then SIGTERM to `lmgrd` and the vendor daemons if they haven't exited after 10 s. Touches only your own processes. Close Libero first, because it loses its license otherwise. |

`99-pfsoc-discovery-uart.rules` is unrelated to licensing. It's the udev rule that makes all of the board's UARTs visible (see the top-level README, "Serial console").

Both scripts expect the daemons and `License.dat` in `~/FlexLM` and the server on port **1702**. `start_libero.sh` hard-codes `LIBERO_BIN=/usr/local/microchip/Libero_SoC_2026.1/Libero_SoC/Designer/bin64/libero`, so update it when Libero is upgraded.

## One-time setup (Ubuntu)

### 1. Download the license daemons

The daemons are **not** part of the Libero installer. Download the Linux daemon package from the ["Daemons" tab on Microchip's Libero download/licensing page](https://www.microchip.com/en-us/products/fpgas-and-plds/fpga-and-soc-design-tools/fpga/licensing#tabs-c3cd7bb734-item-0457bf01b5-tab). Since Libero 2024.2, the 64-bit FlexLM v11.19 daemons are required for all floating licenses:

| Daemon | Licenses |
|---|---|
| `actlmgrd` | Libero |
| `snpslmd` | Synplify Pro ME / Identify ME |
| `saltd` | ModelSim / QuestaSim ME (replaces the old `mgcld`) |

Unpack the package and add the license file:

```bash
mkdir -p ~/FlexLM
tar xzf Linux_Licensing_Daemon_*.tar.gz -C ~/FlexLM --strip-components=1
cp /path/to/License.dat ~/FlexLM/
chmod +x ~/FlexLM/{lmgrd,lmutil,actlmgrd,snpslmd,saltd}
```

### 2. Ubuntu prerequisites

`lmgrd` is linked against the LSB loader, which Ubuntu doesn't ship. Without it, `./lmgrd` fails with a misleading "No such file or directory":

```bash
sudo ln -s /lib64/ld-linux-x86-64.so.2 /lib64/ld-lsb-x86-64.so.3
```

FlexLM writes lock files to `/usr/tmp/.flexlm`, and that directory doesn't exist on Ubuntu:

```bash
sudo mkdir -p /usr/tmp && sudo chmod 1777 /usr/tmp
```

Check that FlexLM sees the host ID (MAC address) the license was generated for:

```bash
~/FlexLM/lmutil lmhostid
```

On this machine it lists the MACs of `enp86s0` and `wlo1` without any changes. If the output is empty or doesn't contain the `HOSTID` from `License.dat`, the usual cause is Ubuntu's predictable interface names, because older FlexLM builds look for `eth0`. The fix is to rename the NIC to `eth0`, either with a netplan `set-name:` matched on the MAC address or with `net.ifnames=0 biosdevname=0` on the kernel command line.

### 3. Edit `License.dat`

Only change the header lines:

```
SERVER <hostname> <HOSTID> 1702
DAEMON actlmgrd /home/<user>/FlexLM/actlmgrd
DAEMON saltd /home/<user>/FlexLM/saltd
VENDOR snpslmd /home/<user>/FlexLM/snpslmd
```

- Replace `<put.hostname.here>` with the output of `hostname`, without the angle brackets. Port 1702 is the default.
- Point each `DAEMON`/`VENDOR` line at its binary using an **absolute path**, because `~` is not expanded. (Here, the `actlmgrd` line still says `PATH/actlmgrd` and the daemon starts anyway, because it is in the same directory as `lmgrd`. An absolute path is the safe choice.)
- Leave the old `mgcld` line commented out.
- **Do not touch** the `HOSTID` or the `FEATURE`/`INCREMENT` lines, because editing them breaks the signatures.
- Only needed when a firewall sits between the server and its clients: add a fixed port to each vendor daemon, e.g. `DAEMON actlmgrd /home/<user>/FlexLM/actlmgrd PORT=1703`. Otherwise the daemons use random ports.

The hostname must resolve locally. Check with `getent hosts $(hostname)`, and add it to `/etc/hosts` if nothing is printed.

### 4. Start Libero

```bash
tools/start_libero.sh &
```

To do the same steps by hand:

```bash
~/FlexLM/lmgrd -c ~/FlexLM/License.dat -l +$HOME/FlexLM/license.log   # as a normal user, not root
~/FlexLM/lmutil lmstat -a -c 1702@localhost                          # all three daemons should be UP

export LM_LICENSE_FILE=1702@localhost
export SNPSLMD_LICENSE_FILE=1702@localhost
export SALT_LICENSE_SERVER=1702@localhost
/usr/local/microchip/Libero_SoC_2026.1/Libero_SoC/Designer/bin64/libero &
```

The `+` before the log path makes `lmgrd` append to the log instead of overwriting it. The environment variables are set in the launcher script rather than in `~/.bashrc`, so they apply only to Libero. If Libero runs on a different machine, use the server's hostname instead of `localhost`.

## Troubleshooting

- **Libero can't check out a license:** run `~/FlexLM/lmutil lmstat -a -c 1702@localhost`. If a daemon isn't UP, the reason is in `~/FlexLM/license.log`. The usual causes are a wrong daemon path, a host ID mismatch, or a hostname that doesn't resolve.
- **Harmless log warning:** `(snpslmd) Warning: Incompatible vendor daemon found.The vendor daemon <actlmgrd> is not supported in <SCL_2024.06> version.` can be ignored.
- **`lmgrd: No such file or directory`** even though the file exists: the LSB loader symlink is missing (step 2).

## Optional: start at boot with systemd

This is not set up on this machine, since `start_libero.sh` starts the server on demand. If you want the server running all the time, create `/etc/systemd/system/flexlm-libero.service`:

```ini
[Unit]
Description=FlexLM license server for Microchip Libero
After=network-online.target
Wants=network-online.target

[Service]
Type=forking
User=<user>
ExecStart=/home/<user>/FlexLM/lmgrd -c /home/<user>/FlexLM/License.dat -l +/home/<user>/FlexLM/license.log
ExecStop=/home/<user>/FlexLM/lmutil lmdown -q -c /home/<user>/FlexLM/License.dat
Restart=on-failure

[Install]
WantedBy=multi-user.target
```

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now flexlm-libero
```

`start_libero.sh` then finds the server already running and launches Libero directly. To stop the server, use `sudo systemctl stop flexlm-libero` instead of `stop_licenser_server.sh`, because with `Restart=on-failure` systemd may restart a server that was killed with SIGTERM.
