#!/usr/bin/env bash
# Byonics MicroFox-50 serial configurator
# Based on MicroFox-50 Manual v0.4 (2026-07-04)
# Serial settings: 115200 baud, 8 data bits, no parity, 1 stop bit (N81)

set -u

BAUD=115200
PORT=""
SERIAL_FD=3
READER_PID=""
OLD_STTY=""

cleanup() {
  if [[ -n "${READER_PID:-}" ]]; then
    kill "$READER_PID" 2>/dev/null || true
    wait "$READER_PID" 2>/dev/null || true
  fi

  if [[ -n "${OLD_STTY:-}" ]]; then
    stty "$OLD_STTY" <&$SERIAL_FD 2>/dev/null || true
  fi

  exec 3>&- 3<&- 2>/dev/null || true
}
trap cleanup EXIT INT TERM

print_header() {
  cat <<'TXT'
Byonics MicroFox-50 Configurator
--------------------------------
Connect the MF-50 with a DATA-capable micro-USB cable and turn it on.
The MF-50 normally appears as a CH340 USB serial device.
TXT
}

find_ports() {
  local p
  PORTS=()
  shopt -s nullglob

  # Common Linux and macOS USB serial device names.
  for p in \
    /dev/ttyUSB* \
    /dev/ttyACM* \
    /dev/cu.wchusbserial* \
    /dev/cu.usbserial* \
    /dev/cu.usbmodem* \
    /dev/cu.SLAB_USBtoUART* \
    /dev/tty.usbserial* \
    /dev/tty.wchusbserial*; do
    PORTS+=("$p")
  done

  shopt -u nullglob
}

choose_port() {
  find_ports

  echo
  if ((${#PORTS[@]})); then
    echo "Detected serial ports:"
    local i
    for ((i=0; i<${#PORTS[@]}; i++)); do
      printf '  %d) %s\n' "$((i+1))" "${PORTS[$i]}"
    done
    echo "  m) Enter a device path manually"
  else
    echo "No common USB serial ports were detected."
    echo "  m) Enter a device path manually"
  fi
  echo "  q) Quit"

  while :; do
    read -r -p "Select serial port: " choice
    case "$choice" in
      q|Q)
        exit 0
        ;;
      m|M)
        read -r -p "Serial device (for example /dev/ttyUSB0): " PORT
        [[ -n "$PORT" ]] && break
        ;;
      ''|*[!0-9]*)
        echo "Please enter a listed number, m, or q."
        ;;
      *)
        if (( choice >= 1 && choice <= ${#PORTS[@]} )); then
          PORT="${PORTS[$((choice-1))]}"
          break
        fi
        echo "That number is not in the list."
        ;;
    esac
  done

  if [[ ! -e "$PORT" ]]; then
    echo "Error: $PORT does not exist." >&2
    exit 1
  fi
}

open_port() {
  # Open once for both reading and writing.
  if ! exec 3<>"$PORT"; then
    cat >&2 <<ERR
Could not open $PORT.
On Linux this is often a permissions issue. Check whether your user has
access to the serial device (commonly via the dialout group).
ERR
    exit 1
  fi

  OLD_STTY="$(stty -g <&$SERIAL_FD 2>/dev/null || true)"

  # 115200 N81, raw I/O, no software flow control.
  if ! stty "$BAUD" cs8 -parenb -cstopb -ixon -ixoff raw -echo <&$SERIAL_FD 2>/dev/null; then
    echo "Error: failed to configure $PORT for ${BAUD} baud N81." >&2
    exit 1
  fi
}

start_reader() {
  if [[ "${1:-}" == 'exit_on_done' ]]; then
    local session_pid=$$
    (
      shopt -s nocasematch
      buffer=''
      while IFS= read -r -N 1 char <&$SERIAL_FD; do
        printf '%s' "$char"
        buffer="${buffer}${char}"
        if ((${#buffer} > 64)); then
          buffer="${buffer: -64}"
        fi
        if [[ "$buffer" =~ settings[[:space:]]+done ]]; then
          kill -USR1 "$session_pid"
          break
        fi
      done
    ) &
  else
    cat <&$SERIAL_FD &
  fi
  READER_PID=$!
}

send_line() {
  # TeraTerm-style Enter is a carriage return. MF-50 accepts settings line-by-line.
  printf '%s\r' "$1" >&$SERIAL_FD
}

interactive_session() {
  echo
  echo "Starting MF-50 configuration mode..."
  echo "The device should print its firmware version and prompt for each setting."
  echo "Press Enter to keep the displayed value, or type a replacement value."
  echo "The program exits automatically when Settings Done is printed."
  echo "Type :quit at any prompt to leave early."
  echo

  trap 'echo; echo "Settings written. Leaving serial session."; exit 0' USR1
  start_reader exit_on_done
  sleep 0.2
  send_line '***'
  # Firmware v0.5 needs a second command after the startup banner.
  sleep 2
  send_line '***'

  local line
  while IFS= read -r line; do
    if [[ "$line" == ':quit' ]]; then
      echo "Leaving serial session."
      break
    fi
    send_line "$line"
  done
}

ask_value() {
  local __var="$1"
  local prompt="$2"
  local value
  read -r -p "$prompt" value
  printf -v "$__var" '%s' "$value"
}

validate_optional_uint() {
  local name="$1" value="$2"
  [[ -z "$value" || "$value" =~ ^[0-9]+$ ]] || {
    echo "Error: $name must be a non-negative integer, or blank to keep the current value." >&2
    return 1
  }
}

quick_wizard() {
  cat <<'TXT'

Quick configuration wizard
--------------------------
Enter a new value for any setting you want to change.
Leave a field blank to keep the MF-50's current value.

TX frequency is entered in kHz; e.g. 146.565 MHz is 146565.
The manual specifies 144000-148000 kHz in 5 kHz steps.
TXT

  local tone_speed tone_duration loop_time initial_delay tx_freq
  local morse_message morse_speed morse_tone tone_sequence power send_battery

  while :; do
    ask_value tone_speed     "Tone Speed (ms) [blank=keep]: "
    validate_optional_uint "Tone Speed" "$tone_speed" && break
  done
  while :; do
    ask_value tone_duration  "Tone Duration (seconds) [blank=keep]: "
    validate_optional_uint "Tone Duration" "$tone_duration" && break
  done
  while :; do
    ask_value loop_time      "Loop Time (seconds) [blank=keep]: "
    validate_optional_uint "Loop Time" "$loop_time" && break
  done
  while :; do
    ask_value initial_delay  "Initial Delay (seconds) [blank=keep]: "
    validate_optional_uint "Initial Delay" "$initial_delay" && break
  done

  while :; do
    ask_value tx_freq "TX Freq in kHz (144000-148000, 5 kHz steps) [blank=keep]: "
    if [[ -z "$tx_freq" ]]; then
      break
    elif [[ "$tx_freq" =~ ^[0-9]+$ ]] && (( tx_freq >= 144000 && tx_freq <= 148000 && tx_freq % 5 == 0 )); then
      break
    else
      echo "Please enter 144000-148000 in 5 kHz steps, or leave blank."
    fi
  done

  ask_value morse_message "Morse Message / callsign [blank=keep]: "

  while :; do
    ask_value morse_speed "Morse Speed (WPM) [blank=keep]: "
    validate_optional_uint "Morse Speed" "$morse_speed" && break
  done

  while :; do
    ask_value morse_tone "Morse Tone code (2-49; 25 = 831 Hz) [blank=keep]: "
    if [[ -z "$morse_tone" ]]; then
      break
    elif [[ "$morse_tone" =~ ^[0-9]+$ ]] && (( morse_tone >= 2 && morse_tone <= 49 )); then
      break
    else
      echo "Please enter a tone code from 2 through 49, or leave blank."
    fi
  done

  ask_value tone_sequence "Tone Sequence [blank=keep]: "

  while :; do
    ask_value power "Power level (0-50) [blank=keep]: "
    if [[ -z "$power" ]]; then
      break
    elif [[ "$power" =~ ^[0-9]+$ ]] && (( power >= 0 && power <= 50 )); then
      break
    else
      echo "Please enter 0 through 50, or leave blank."
    fi
  done

  while :; do
    ask_value send_battery "Send Battery in Morse? (0=no, 1=yes) [blank=keep]: "
    [[ -z "$send_battery" || "$send_battery" == 0 || "$send_battery" == 1 ]] && break
    echo "Please enter 0, 1, or leave blank."
  done

  echo
  echo "About to send this configuration to $PORT:"
  printf '  Tone Speed:      %s\n' "${tone_speed:-keep}"
  printf '  Tone Duration:   %s\n' "${tone_duration:-keep}"
  printf '  Loop Time:       %s\n' "${loop_time:-keep}"
  printf '  Initial Delay:   %s\n' "${initial_delay:-keep}"
  printf '  TX Freq:         %s\n' "${tx_freq:-keep}"
  printf '  Morse Message:   %s\n' "${morse_message:-keep}"
  printf '  Morse Speed:     %s\n' "${morse_speed:-keep}"
  printf '  Morse Tone:      %s\n' "${morse_tone:-keep}"
  printf '  Tone Sequence:   %s\n' "${tone_sequence:-keep}"
  printf '  Power:           %s\n' "${power:-keep}"
  printf '  Send Battery:    %s\n' "${send_battery:-keep}"
  echo

  read -r -p "Write these settings? [y/N]: " confirm
  [[ "$confirm" =~ ^[Yy]$ ]] || {
    echo "Cancelled; nothing was sent."
    return
  }

  start_reader
  sleep 0.2
  send_line '***'
  sleep 0.6

  # The MF-50 asks for these settings in this order in manual v0.4.
  local values=(
    "$tone_speed"
    "$tone_duration"
    "$loop_time"
    "$initial_delay"
    "$tx_freq"
    "$morse_message"
    "$morse_speed"
    "$morse_tone"
    "$tone_sequence"
    "$power"
    "$send_battery"
  )

  local v
  for v in "${values[@]}"; do
    send_line "$v"
    sleep 0.35
  done

  # Give the device time to print "Settings Done".
  sleep 1.2
  echo
  echo "Configuration sequence sent. Look above for 'Settings Done'."
}

main_menu() {
  echo
  echo "Connected to $PORT at ${BAUD} baud, N81."
  echo
  echo "Choose mode:"
  echo "  1) Interactive MF-50 setup (safest; follows device prompts)"
  echo "  2) Quick wizard (collect values first, then send them in manual order)"
  echo "  q) Quit"

  while :; do
    read -r -p "Mode: " mode
    case "$mode" in
      1) interactive_session; break ;;
      2) quick_wizard; break ;;
      q|Q) exit 0 ;;
      *) echo "Choose 1, 2, or q." ;;
    esac
  done
}

print_header
choose_port
open_port
main_menu
