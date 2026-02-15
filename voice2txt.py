#!/usr/bin/env python3
"""Voice2txt — lightweight push-to-talk transcription using Deepgram Nova-3."""

import io
import math
import os
import struct
import subprocess
import threading
import time
import tkinter as tk
import wave

import pyperclip
import sounddevice as sd
from deepgram import DeepgramClient
from pynput import keyboard


# ── Audio settings ──────────────────────────────────────────────────────────
SAMPLE_RATE = 16000
CHANNELS = 1
CHUNK_SIZE = 4096  # ~256ms at 16kHz

# ── Hotkey timing ───────────────────────────────────────────────────────────
DOUBLE_TAP_WINDOW = 0.3  # seconds

# ── State ───────────────────────────────────────────────────────────────────
STATE_IDLE = "IDLE"
STATE_RECORDING = "RECORDING"


class Overlay:
    """Floating 3D waterfall waveform — no frame, no background."""

    WIDTH = 180
    HEIGHT = 120
    NUM_LINES = 16       # number of waveform slices stacked
    WAVE_POINTS = 28     # points per waveform line (fewer = smoother)

    def __init__(self, root: tk.Tk):
        self.root = root
        self.win = tk.Toplevel(root)
        self.win.title("Voice2txt")
        self.win.overrideredirect(True)
        self.win.attributes("-topmost", True)

        # Transparent background on macOS
        self.win.attributes("-transparent", True)
        self.win.config(bg="systemTransparent")

        self.canvas = tk.Canvas(
            self.win, width=self.WIDTH, height=self.HEIGHT,
            bg="systemTransparent", highlightthickness=0,
        )
        self.canvas.pack()

        # Rolling buffer of waveform snapshots (newest first)
        self._waveforms: list[list[float]] = []
        self._pending_waveform: list[float] | None = None
        self._transcribing = False
        self._frame = 0

        self.win.withdraw()

    def show(self):
        self._reset()
        self.win.deiconify()
        self.win.lift()
        self._draw()

    def show_on_mouse_screen(self):
        self._reset()
        x, y = self._get_overlay_position()
        self.win.geometry(f"{self.WIDTH}x{self.HEIGHT}+{x}+{y}")
        self.win.deiconify()
        self.win.lift()
        self._draw()

    def _reset(self):
        self._waveforms = []
        self._pending_waveform = None
        self._transcribing = False
        self._frame = 0

    def _get_overlay_position(self) -> tuple[int, int]:
        try:
            from AppKit import NSScreen, NSEvent
            mouse = NSEvent.mouseLocation()
            primary_h = NSScreen.screens()[0].frame().size.height
            for screen in NSScreen.screens():
                f = screen.frame()
                if (f.origin.x <= mouse.x < f.origin.x + f.size.width and
                        f.origin.y <= mouse.y < f.origin.y + f.size.height):
                    vf = screen.visibleFrame()
                    tk_left = int(vf.origin.x)
                    tk_top = int(primary_h - vf.origin.y - vf.size.height)
                    tk_w = int(vf.size.width)
                    tk_h = int(vf.size.height)
                    x = tk_left + (tk_w - self.WIDTH) // 2
                    y = tk_top + tk_h - self.HEIGHT - 20
                    return x, y
        except Exception:
            pass
        sx = self.root.winfo_screenwidth()
        sy = self.root.winfo_screenheight()
        return (sx - self.WIDTH) // 2, sy - self.HEIGHT - 20

    def hide(self):
        self.win.withdraw()

    def show_transcribing(self):
        self._transcribing = True

    def update_waveform(self, samples: list[float]):
        """Receive a downsampled waveform snapshot from audio callback."""
        self._pending_waveform = samples

    def update_levels(self, rms: float):
        """Fallback — ignored, we use update_waveform instead."""
        pass

    def _draw(self):
        if not self.win.winfo_viewable():
            return

        c = self.canvas
        c.delete("all")
        self._frame += 1

        # Ingest new waveform if available
        if self._pending_waveform is not None:
            self._waveforms.insert(0, self._pending_waveform)
            self._pending_waveform = None
            if len(self._waveforms) > self.NUM_LINES:
                self._waveforms.pop()

        base_y = self.HEIGHT - 6  # bottom baseline
        line_spacing = 5          # vertical gap between stacked lines
        max_amplitude = 40        # max waveform displacement in pixels
        wave_width = self.WIDTH - 16  # horizontal span of each waveform

        if self._transcribing:
            # Gentle idle pulse while transcribing
            t = self._frame * 0.05
            for row in range(min(8, self.NUM_LINES)):
                frac = row / self.NUM_LINES
                y = base_y - row * line_spacing
                alpha = 1.0 - frac * 0.7
                g = int(min(255, 160 * alpha))
                b = int(min(255, 200 * alpha))
                color = f"#00{g:02x}{b:02x}"
                pts = []
                for i in range(self.WAVE_POINTS):
                    px = 8 + (i / (self.WAVE_POINTS - 1)) * wave_width
                    dy = math.sin(t + i * 0.3 + row * 0.5) * 3 * alpha
                    pts.extend([px, y + dy])
                if len(pts) >= 4:
                    c.create_line(*pts, fill=color, width=1, smooth=True)
        else:
            # 3D waterfall: draw back-to-front for proper layering
            for row in range(len(self._waveforms) - 1, -1, -1):
                waveform = self._waveforms[row]
                frac = row / max(self.NUM_LINES - 1, 1)
                y = base_y - row * line_spacing

                # Perspective: lines further back are narrower
                perspective = 1.0 - frac * 0.4
                w = wave_width * perspective
                x_offset = (self.WIDTH - w) / 2

                # Color: front=bright cyan, fades to dim blue-purple
                brightness = 1.0 - frac * 0.7
                r_val = int(min(255, 50 * frac))
                g_val = int(min(255, 255 * brightness))
                b_val = int(min(255, 255 * brightness))
                color = f"#{r_val:02x}{g_val:02x}{b_val:02x}"

                pts = []
                for i, amp in enumerate(waveform):
                    px = x_offset + (i / max(len(waveform) - 1, 1)) * w
                    dy = amp * max_amplitude * perspective
                    pts.extend([px, y - dy])

                if len(pts) >= 4:
                    c.create_line(*pts, fill=color, width=1, smooth=True)

        # ~30fps
        self.root.after(33, self._draw)


class HotkeyListener:
    """Global keyboard listener: double-tap Ctrl (long) and hold Right Option (short)."""

    def __init__(self, on_start, on_stop):
        self.on_start = on_start  # callback(mode)
        self.on_stop = on_stop    # callback()
        self.state = STATE_IDLE
        self._ctrl_times: list[float] = []
        self._right_option_held = False
        self._listener = keyboard.Listener(
            on_press=self._on_press,
            on_release=self._on_release,
        )
        self._listener.daemon = True

    def start(self):
        self._listener.start()

    def _on_press(self, key):
        now = time.time()

        # Right Option (Alt_R) hold → short mode
        if key == keyboard.Key.alt_r:
            if self.state == STATE_IDLE and not self._right_option_held:
                self._right_option_held = True
                self.state = STATE_RECORDING
                self.on_start("short")
            return

        # Ctrl press handling
        if key in (keyboard.Key.ctrl_l, keyboard.Key.ctrl_r, keyboard.Key.ctrl):
            if self.state == STATE_RECORDING and not self._right_option_held:
                # Single Ctrl stops a long recording
                self.state = STATE_IDLE
                self._ctrl_times.clear()
                self.on_stop()
                return

            # Track press times for double-tap detection
            self._ctrl_times = [t for t in self._ctrl_times if now - t < DOUBLE_TAP_WINDOW]
            self._ctrl_times.append(now)

            if len(self._ctrl_times) >= 2:
                self._ctrl_times.clear()
                if self.state == STATE_IDLE:
                    self.state = STATE_RECORDING
                    self.on_start("long")

    def _on_release(self, key):
        if key == keyboard.Key.alt_r:
            if self._right_option_held:
                self._right_option_held = False
                if self.state == STATE_RECORDING:
                    self.state = STATE_IDLE
                    self.on_stop()


class Voice2txt:
    """Main controller tying overlay, hotkeys, audio, and Deepgram together."""

    def __init__(self):
        api_key = os.environ.get("DEEPGRAM_API_KEY")
        if not api_key:
            # Try reading from file next to script
            key_file = os.path.join(os.path.dirname(os.path.abspath(__file__)), "deepgram")
            if os.path.exists(key_file):
                api_key = open(key_file).read().strip()
        if not api_key:
            print("ERROR: Set DEEPGRAM_API_KEY env var or create a 'deepgram' file with your key.")
            raise SystemExit(1)

        self._client = DeepgramClient(api_key=api_key)

        # tkinter root (hidden, drives the mainloop)
        self.root = tk.Tk()
        self.root.withdraw()

        self.overlay = Overlay(self.root)
        self.hotkeys = HotkeyListener(
            on_start=self._on_recording_start,
            on_stop=self._on_recording_stop,
        )

        self._audio_stream: sd.InputStream | None = None
        self._audio_chunks: list[bytes] = []
        self._recording = False
        self._pending_waveform: list[float] | None = None
        self._frontmost_app: str | None = None

        # Start UI polling
        self.root.after(50, self._poll_ui)

    def run(self):
        print("Voice2txt ready.", flush=True)
        print("  Double-tap Ctrl   → start long recording (Ctrl to stop)", flush=True)
        print("  Hold Right Option → short recording (release to stop)", flush=True)
        print("  Transcript auto-pastes into active app", flush=True)
        self.hotkeys.start()
        self.root.mainloop()

    # ── callbacks (called from non-main threads) ────────────────────────────

    def _on_recording_start(self, mode: str):
        # Remember the frontmost app so we can reactivate it for pasting
        try:
            result = subprocess.run(
                ["osascript", "-e", 'tell application "System Events" to get name of first application process whose frontmost is true'],
                capture_output=True, text=True, timeout=2,
            )
            self._frontmost_app = result.stdout.strip() or None
            print(f"Frontmost app: {self._frontmost_app}", flush=True)
        except Exception:
            self._frontmost_app = None

        self._recording = True
        self._audio_chunks = []

        # Start audio capture
        self._audio_stream = sd.InputStream(
            samplerate=SAMPLE_RATE,
            channels=CHANNELS,
            dtype="int16",
            blocksize=CHUNK_SIZE,
            callback=self._audio_callback,
        )
        self._audio_stream.start()

        # Show overlay on the screen where the mouse is
        self.root.after(0, self.overlay.show_on_mouse_screen)
        print(f"Recording started ({mode} mode)", flush=True)

        # Audio feedback
        _play_sound("/System/Library/Sounds/Tink.aiff")

    def _on_recording_stop(self):
        self._recording = False
        print("Recording stopped", flush=True)

        # Stop audio
        if self._audio_stream:
            self._audio_stream.stop()
            self._audio_stream.close()
            self._audio_stream = None

        # Show transcribing status
        self.root.after(0, self.overlay.show_transcribing)

        # Audio feedback
        _play_sound("/System/Library/Sounds/Pop.aiff")

        # Transcribe in background thread to avoid blocking
        chunks = self._audio_chunks[:]
        self._audio_chunks = []
        threading.Thread(target=self._transcribe, args=(chunks,), daemon=True).start()

    def _transcribe(self, chunks: list[bytes]):
        """Send recorded audio to Deepgram pre-recorded API."""
        if not chunks:
            print("(no audio captured)", flush=True)
            self.root.after(0, self.overlay.hide)
            return

        # Build WAV in memory
        audio_data = b"".join(chunks)
        print(f"Audio: {len(chunks)} chunks, {len(audio_data)} bytes, {len(audio_data)/SAMPLE_RATE/2:.1f}s", flush=True)
        buf = io.BytesIO()
        with wave.open(buf, "wb") as wf:
            wf.setnchannels(CHANNELS)
            wf.setsampwidth(2)  # 16-bit
            wf.setframerate(SAMPLE_RATE)
            wf.writeframes(audio_data)
        wav_bytes = buf.getvalue()

        try:
            print("Sending to Deepgram...", flush=True)
            response = self._client.listen.v1.media.transcribe_file(
                request=wav_bytes,
                model="nova-3",
                language="en",
                smart_format=True,
            )
            transcript = response.results.channels[0].alternatives[0].transcript
        except Exception as e:
            print(f"Transcription error: {type(e).__name__}: {e}", flush=True)
            self.root.after(0, self.overlay.hide)
            return

        # Hide overlay first so focus returns to user's app
        self.root.after(0, self.overlay.hide)

        if transcript:
            pyperclip.copy(transcript)
            print(f"Copied: {transcript[:80]}{'...' if len(transcript) > 80 else ''}", flush=True)
            # Wait for overlay to dismiss
            time.sleep(0.15)
            # Reactivate the app that was focused before recording, then paste
            app = self._frontmost_app
            if app:
                script = f'''
                    tell application "{app}" to activate
                    delay 0.1
                    tell application "System Events" to keystroke "v" using command down
                '''
            else:
                script = 'tell application "System Events" to keystroke "v" using command down'
            subprocess.run(
                ["osascript", "-e", script],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
            print(f"Auto-pasted into {app or 'active app'}", flush=True)
        else:
            print("(no speech detected)", flush=True)

    def _audio_callback(self, indata, frames, time_info, status):
        """Called by sounddevice from its own thread for each audio chunk."""
        if not self._recording:
            return
        raw = bytes(indata)
        self._audio_chunks.append(raw)

        # Downsample to ~28 points with averaging for smooth waveform
        samples = struct.unpack(f"<{len(raw)//2}h", raw)
        if not samples:
            return
        n_points = 28
        chunk_size = max(1, len(samples) // n_points)
        waveform = []
        for p in range(n_points):
            start = p * chunk_size
            end = min(start + chunk_size, len(samples))
            # RMS of chunk — smooth envelope, not raw samples
            chunk_rms = math.sqrt(sum(s * s for s in samples[start:end]) / max(1, end - start)) / 32768.0
            boosted = min(1.0, (chunk_rms ** 0.5) * 2.5) if chunk_rms > 0.005 else 0.0
            waveform.append(boosted)
        self._pending_waveform = waveform

    # ── UI polling (main thread) ────────────────────────────────────────────

    def _poll_ui(self):
        if self._pending_waveform is not None:
            self.overlay.update_waveform(self._pending_waveform)
            self._pending_waveform = None
        self.root.after(50, self._poll_ui)


def _play_sound(path: str):
    """Play a macOS system sound asynchronously."""
    if os.path.exists(path):
        subprocess.Popen(
            ["afplay", path],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )


if __name__ == "__main__":
    Voice2txt().run()
