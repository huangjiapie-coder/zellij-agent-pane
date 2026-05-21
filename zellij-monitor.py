#!/usr/bin/env python3
"""Monitor agent transcript file and format output for zellij pane display."""
import sys
import json
import time
import os

def format_block(block):
    """Format a single content block."""
    btype = block.get("type", "")
    if btype == "text":
        text = block.get("text", "")
        return text[:1500] if text else None
    elif btype == "thinking":
        thinking = block.get("thinking", "")
        return f"\033[2m[thinking]\033[0m {thinking[:500]}" if thinking else None
    elif btype == "tool_use":
        name = block.get("name", "")
        inp = block.get("input", {})
        cmd = inp.get("command", "") or inp.get("url", "") or json.dumps(inp, ensure_ascii=False)
        summary = str(cmd)[:300].replace("\\n", " ").replace("\\r", "")
        return f"\n  \033[1;33m→ {name}\033[0m {summary}"
    elif btype == "tool_result":
        result = block.get("content", "")
        if isinstance(result, list):
            result = " ".join(c.get("text", "") for c in result if c.get("type") == "text")
        if result:
            text = str(result)
            # Strip noisy system messages
            for noise in [
                "REMINDER: YOU MUST include the sources above in your response to the user using markdown hyperlinks.",
                "REMINDER: You MUST include the sources above in your response to the user using markdown hyperlinks.",
                "REMINDER: You MUST include the sources in your response",
                "REMINDER: YOU MUST include the sources",
            ]:
                text = text.replace(noise, "")
            # Shorten common permission denied messages
            if len(text) > 200 and "denied" in text.lower():
                # Extract just the first meaningful line
                lines = text.strip().split("\n")
                text = lines[0][:200]
            text = text.strip().lstrip("\n,; ")
            if text:
                return f"\n  \033[2m[result]\033[0m {text[:500]}"
    return None


def format_transcript(line):
    try:
        d = json.loads(line)
        dtype = d.get("type", "")
        msg = d.get("message", {})
        role = msg.get("role", "")
        content = msg.get("content", "")

        # Handle attachment (skill listing, etc.)
        if dtype == "attachment":
            attachment = d.get("attachment", {})
            atype = attachment.get("type", "")
            if atype == "skill_listing":
                sc = attachment.get("skillCount", 0)
                return f"\n\033[1;35m[SKILLS]\033[0m loaded {sc} skills"
            return None

        # Build header per role
        header = None
        if role == "user":
            header = "\n\033[1;32m[USER]\033[0m"
        elif role == "assistant":
            header = "\n\033[1;36m[ASSISTANT]\033[0m"

        # Process content
        if isinstance(content, list):
            lines = []
            for block in content:
                formatted = format_block(block)
                if formatted:
                    lines.append(formatted)

            if not lines:
                return None  # Skip empty messages (e.g. pure thinking blocks)

            output = header if header else ""
            for l in lines:
                output += "\n" + l
            return output

        elif isinstance(content, str) and content.strip():
            output = header if header else ""
            output += "\n" + str(content)[:1500]
            return output

        return None

    except json.JSONDecodeError:
        pass
    return None


def main():
    # Wrap everything in try/except so the pane shows errors instead of flashing away
    try:
        _main()
    except Exception as e:
        print(f"\n[ERROR] Monitor crashed unexpectedly: {e}")
        import traceback
        traceback.print_exc()
        print("\n[INFO] Pane will close in 60 seconds...")
        time.sleep(60)


def _main():
    # Get agent_id from argv, then read path and type from temp file
    # (to avoid MSYS2/zellij encoding corruption of Chinese chars in cmd line args)
    agent_id = sys.argv[1]
    # ALWAYS use ~/.claude/ for temp metadata files (cross-machine consistent)
    home = os.path.expanduser("~")
    tmp_path = os.path.join(home, ".claude", f".mon-{agent_id}.json")

    print(f"\033[1;34m=== Agent Monitor Starting ===\033[0m")
    print(f"Agent ID: {agent_id}")
    print(f"Temp file: {tmp_path}")
    print(f"Waiting for temp file...")

    # Wait for temp file to appear
    waited = 0
    while not os.path.exists(tmp_path):
        time.sleep(0.2)
        waited += 1
        if waited >= 100:  # 20 seconds
            print(f"\n[ERROR] Timeout waiting for temp file: {tmp_path}")
            print("[INFO] Pane will close in 30 seconds...")
            time.sleep(30)
            sys.exit(1)

    try:
        # Try multiple encodings
        content = None
        for encoding in ['utf-8-sig', 'utf-8', 'gbk', 'cp1252']:
            try:
                with open(tmp_path, "r", encoding=encoding) as f:
                    content = f.read()
                    meta = json.loads(content)
                    transcript_path = meta["path"]
                    agent_type = meta["type"]
                    print(f"\033[1;32m✓ Read temp file with encoding: {encoding}\033[0m")
                    break
            except (UnicodeDecodeError, json.JSONDecodeError) as e:
                print(f"\033[2m  Tried {encoding}: {type(e).__name__}\033[0m")
                continue

        if content is None:
            print(f"\n[ERROR] Failed to read temp file with any encoding")
            print("[INFO] Pane will close in 30 seconds...")
            time.sleep(30)
            sys.exit(1)

    except Exception as e:
        print(f"\n[ERROR] Cannot read agent metadata: {e}")
        import traceback
        traceback.print_exc()
        print(f"[INFO] Temp file exists: {os.path.exists(tmp_path)}")
        if os.path.exists(tmp_path):
            try:
                print(f"[INFO] File size: {os.path.getsize(tmp_path)} bytes")
                with open(tmp_path, 'rb') as f:
                    raw = f.read(200)
                    print(f"[INFO] Raw first 200 bytes: {raw!r}")
            except:
                pass
        print("[INFO] Pane will close in 30 seconds...")
        time.sleep(30)
        sys.exit(1)

    print(f"\n\033[1;34m=== Agent: {agent_type} ===\033[0m")
    print(f"Transcript: {transcript_path}")
    print("-" * 60)

    # Wait for file to appear (max 60 seconds)
    waited = 0
    while not os.path.exists(transcript_path):
        time.sleep(0.2)
        waited += 1
        if waited % 50 == 0:  # every 10 seconds
            print(f"Still waiting for transcript... ({waited * 0.2:.0f}s)")
        if waited >= 300:  # 60 seconds
            print(f"\n[ERROR] Timeout waiting for transcript file:\n  {transcript_path}")
            print("[INFO] The agent may have finished before the transcript was created.")
            print("[INFO] Pane will close in 30 seconds...")
            time.sleep(30)
            sys.exit(1)

    print("Transcript found! Monitoring...")
    print("-" * 60)

    # Read-written lines we've already seen
    seen_lines = set()
    last_role = None  # Track last displayed role to avoid duplicate headers

    while True:
        try:
            if os.path.exists(transcript_path):
                # Try multiple encodings
                for encoding in ['utf-8-sig', 'utf-8', 'gbk']:
                    try:
                        with open(transcript_path, "r", encoding=encoding, errors="replace") as f:
                            for line in f:
                                line_stripped = line.strip()
                                if not line_stripped or line_stripped in seen_lines:
                                    continue
                                seen_lines.add(line_stripped)
                                output = format_transcript(line_stripped)
                                if output:
                                    # Suppress duplicate [ASSISTANT] headers for consecutive assistant blocks
                                    if "[ASSISTANT]" in output and last_role == "assistant":
                                        # Remove the header line, keep content
                                        output = output.replace("\n\033[1;36m[ASSISTANT]\033[0m", "")
                                    if "[USER]" in output:
                                        last_role = "user"
                                    elif "[ASSISTANT]" in output:
                                        last_role = "assistant"
                                    print(output)
                                    sys.stdout.flush()
                        break  # success, stop trying encodings
                    except UnicodeDecodeError:
                        continue
        except Exception as e:
            print(f"\n\033[31m[WARNING] Error reading transcript: {e}\033[0m")
        time.sleep(0.3)


if __name__ == "__main__":
    # Force UTF-8 for stdout (handles Chinese characters in Windows terminals)
    if hasattr(sys.stdout, "reconfigure"):
        try:
            sys.stdout.reconfigure(encoding="utf-8")
        except:
            pass
    main()

