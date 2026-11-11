"""Unlock a GNOME keyring collection with the password on stdin, no prompt.

Fingerprint logins hand PAM no password, so the keyring stays locked;
keyring-tpm-unlock.service feeds this the TPM-sealed password instead.
Usage: keyring-unlock [collection-object-path]  (default: the default keyring)
"""
import sys

from jeepney import DBusAddress, new_method_call
from jeepney.io.blocking import open_dbus_connection
from jeepney.wrappers import unwrap_msg

password = sys.stdin.buffer.read().rstrip(b"\n")
if not password:
    sys.exit("keyring-unlock: no password on stdin")

bus = open_dbus_connection(bus="SESSION")


def call(interface, method, signature, body):
    address = DBusAddress(
        "/org/freedesktop/secrets",
        bus_name="org.freedesktop.secrets",
        interface=interface,
    )
    message = new_method_call(address, method, signature, body)
    return unwrap_msg(bus.send_and_get_reply(message))


service = "org.freedesktop.Secret.Service"
if len(sys.argv) > 1:
    collection = sys.argv[1]
else:
    collection = call(service, "ReadAlias", "s", ("default",))[0]
if collection == "/":
    sys.exit("keyring-unlock: no default keyring")

# "plain" session: the password travels over the local session bus only.
session = call(service, "OpenSession", "sv", ("plain", ("s", "")))[1]
call(
    "org.gnome.keyring.InternalUnsupportedGuiltRiddenInterface",
    "UnlockWithMasterPassword",
    "o(oayays)",
    (collection, (session, b"", password, "text/plain")),
)
