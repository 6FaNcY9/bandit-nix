"""Telegram login. Read-only use; telethon is imported lazily so other commands work without it."""
import contextlib
import getpass
import json
import os
import sys

CHANNELS = {"WildKernelsTG": "all", "yurikernel": "all", "BakaSU_Grp": "admins"}
CREDENTIALS = os.path.expanduser("~/.config/pkt/telegram.json")


def load_credentials(path=CREDENTIALS):
    try:
        st = os.stat(path)
    except FileNotFoundError:
        try:
            return int(getpass.getpass("API id: ")), getpass.getpass("API hash: ")
        except ValueError:
            raise ValueError("API id must be a number") from None
    if st.st_mode & 0o077:
        raise PermissionError(f"{path} must not be accessible by group/other (chmod 600)")
    try:
        with open(path) as f:
            d = json.load(f)
        return int(d["api_id"]), str(d["api_hash"])
    except OSError:
        raise OSError(f"cannot read {path}") from None
    except (ValueError, KeyError, TypeError):
        raise ValueError(f"{path} must be JSON with api_id and api_hash") from None


def _telethon_client(api_id, api_hash):
    from telethon import TelegramClient
    from telethon.sessions import StringSession
    return TelegramClient(StringSession(), api_id, api_hash)


CODE_PLACES = {
    "SentCodeTypeApp": "the Telegram app, chat named Telegram (or another logged-in device)",
    "SentCodeTypeSms": "SMS",
    "SentCodeTypeEmailCode": "your login email",
    "SentCodeTypeCall": "a phone call",
    "SentCodeTypeFragmentSms": "Fragment (fragment.com), for an anonymous number",
}


def _show_code_delivery(client):
    """start() hides where Telegram sent the code, and that is what a user waiting for one needs."""
    send = client.send_code_request

    async def showing(*a, **k):
        sent = await send(*a, **k)
        name = type(sent.type).__name__
        print("Telegram says the code goes to:", CODE_PLACES.get(name, name), file=sys.stderr)
        if sent.next_type is not None:
            print(f"Fallback: {type(sent.next_type).__name__} after {sent.timeout} seconds", file=sys.stderr)
        return sent
    client.send_code_request = showing


@contextlib.asynccontextmanager
async def session(api_id, api_hash, factory=_telethon_client):
    client = factory(api_id, api_hash)
    # 0: any Telegram wait raises FloodWaitError instead of silently sleeping
    client.flood_sleep_threshold = 0
    logged_in = False
    if hasattr(client, "send_code_request"):
        _show_code_delivery(client)
    try:
        await client.start()  # phone, code and 2FA are prompted by telethon itself
        logged_in = True
        yield client
    finally:
        # real log_out() returns False on RPC errors without disconnecting
        try:
            ok = bool(await client.log_out())
        except Exception:
            ok = False
        if not ok:
            try:
                await client.disconnect()
            except Exception:
                pass
            if logged_in:
                print("warning: Telegram logout was not confirmed; check and end the session in "
                      "Telegram > Settings > Devices", file=sys.stderr)
