# MicroFox-50 Configurator

A Bash script for configuring a Byonics MicroFox-50 over USB serial. It detects common Linux and macOS serial device paths and connects at 115200 baud, 8 data bits, no parity, and 1 stop bit.

## Requirements

- Bash 4 or later and the standard `stty` utility.
- A powered-on MicroFox-50 connected with a data-capable micro-USB cable.
- Read/write access to its serial device, typically `/dev/ttyUSB0` on Linux.

On Linux, serial access commonly requires membership in the `dialout` group. If your system uses that group, run:

```sh
sudo usermod -aG dialout "$USER"
```

Log out and back in for the new group membership to take effect. On macOS, use a current Bash installation if the system Bash is too old.

## Usage

```sh
git clone https://github.com/MaxFreedman/mf50-config.git
cd mf50-config
bash ./mf50-config.sh
```

The repository is private, so cloning requires an authenticated account with access.

Select a detected serial port, or choose `m` to enter its path manually. Then select a configuration mode.

### Interactive mode (recommended)

Choose `1` to follow the device's prompts. Press Enter to keep each displayed setting, or enter a replacement value.

The script sends `***` twice, with a two-second pause between commands, to enter configuration on firmware v0.5. When the device reports `Settings Done`, the script exits automatically and restores the previous serial settings. Type `:quit` to leave the session early; doing so does not complete the configuration sequence.

### Quick wizard

Choose `2` to collect values before sending them. Leave fields blank to keep their current values, review the summary, and confirm with `y` to send them.

The wizard sends the 11 settings in the order specified by manual v0.4, using fixed delays. Check the device output for `Settings Done` to confirm completion. This mode has not been verified on the connected firmware v0.5 device; use interactive mode for that firmware.

## Settings

The script supports tone speed, tone duration, loop time, initial delay, transmit frequency, Morse message, Morse speed, Morse tone, tone sequence, power, and the battery announcement option.

Transmit frequency is entered in kHz: for example, `146565` means 146.565 MHz. The wizard accepts 144000–148000 kHz in 5 kHz steps, Morse tone codes 2–49, power levels 0–50, and `0` or `1` for the battery announcement.

## Verification

Interactive mode was tested on a connected MicroFox-50 running firmware v0.5 under Linux. The two-command startup opened the prompts automatically, all 11 existing settings were retained, and the script exited with status `0` after `Settings Done`.

To check shell syntax without connecting a device:

```sh
bash -n mf50-config.sh
```
