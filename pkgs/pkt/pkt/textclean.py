import re


def sanitize(text):
    """Untrusted text: no control characters (\\r, escapes), no bidi controls. Newline and tab stay."""
    return re.sub(r"[^\n\t -~\u00a0-\U0010ffff]|[\u061c\u200e\u200f\u202a-\u202e\u2066-\u2069]", "?", text)
