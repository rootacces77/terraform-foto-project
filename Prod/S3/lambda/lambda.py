import os
import json
import time
import base64
import re
import hmac
import hashlib
import struct
from typing import Any, Dict, Optional, Tuple, List
from urllib.parse import quote

import boto3
from botocore.exceptions import ClientError

from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import padding


# =============================================================================
# Config (env vars)
# =============================================================================
CLOUDFRONT_DOMAIN = os.environ["CLOUDFRONT_DOMAIN"].strip()  # e.g. gallery.project-practice.com
CLOUDFRONT_KEY_PAIR_ID = os.environ["CLOUDFRONT_KEY_PAIR_ID"].strip()
PRIVATE_KEY_SECRET_ARN = os.environ["CLOUDFRONT_PRIVATE_KEY_SECRET_ARN"].strip()
GALLERY_BUCKET = os.environ["GALLERY_BUCKET"].strip()

# Prefix under which client folders live (required). Example: "gallery" or "gallery/"
ALLOWED_PREFIX_RAW = os.getenv("ALLOWED_FOLDER_PREFIX", "").strip().lstrip("/")

# Cookie TTL bounds (in seconds)
DEFAULT_TTL_SECONDS = int(os.getenv("DEFAULT_TTL_SECONDS", "86400"))   # 24 hours default
MAX_TTL_SECONDS = int(os.getenv("MAX_TTL_SECONDS", "86400"))           # 24 hours max

# Share-link validity (independent of cookie TTL) (seconds)
DEFAULT_LINK_TTL_SECONDS = int(os.getenv("DEFAULT_LINK_TTL_SECONDS", str(7 * 24 * 3600)))  # 7 days

# Link signing secret (HMAC). Required for stateless tokens.
LINK_SIGNING_SECRET_RAW = os.getenv("LINK_SIGNING_SECRET", "").strip()
if not LINK_SIGNING_SECRET_RAW:
    raise RuntimeError("Missing required env var: LINK_SIGNING_SECRET")
LINK_SIGNING_SECRET = LINK_SIGNING_SECRET_RAW.encode("utf-8")

# Error page path on CloudFront domain (static)
ERROR_PAGE_PATH = os.getenv("ERROR_PAGE_PATH", "/site/error.html").strip()

# Cookie attributes
COOKIE_SECURE = os.getenv("COOKIE_SECURE", "true").lower() == "true"
COOKIE_HTTPONLY = os.getenv("COOKIE_HTTPONLY", "true").lower() == "true"
COOKIE_SAMESITE = os.getenv("COOKIE_SAMESITE", "None")  # "Lax" / "Strict" / "None"
COOKIE_SET_MAX_AGE = os.getenv("COOKIE_SET_MAX_AGE", "true").lower() == "true"

COOKIE_DOMAIN = os.getenv("COOKIE_DOMAIN", CLOUDFRONT_DOMAIN).strip()
COOKIE_PATH = os.getenv("COOKIE_PATH", "/").strip()

# Paths
OPEN_PATH = os.getenv("OPEN_PATH", "/open").strip()
LIST_PATH = os.getenv("LIST_PATH", "/list").strip()
SIGN_PATH = os.getenv("SIGN_PATH", "/sign").strip()

# Your static app entry point
GALLERY_INDEX_PATH = os.getenv("GALLERY_INDEX_PATH", "/site/index.html").strip()

MAX_LIST_KEYS = int(os.getenv("MAX_LIST_KEYS", "500"))

ALLOWED_IMAGE_EXT = set(
    e.strip().lower()
    for e in os.getenv("ALLOWED_IMAGE_EXT", ".jpg,.jpeg,.png,.webp,.gif").split(",")
    if e.strip()
)

ALLOWED_ZIP_EXT = set(
    e.strip().lower()
    for e in os.getenv("ALLOWED_ZIP_EXT", ".zip").split(",")
    if e.strip()
)

# Normalize base prefix once (must end with "/")
BASE_PREFIX = ALLOWED_PREFIX_RAW.strip().strip("/")
if not BASE_PREFIX:
    raise RuntimeError("ALLOWED_FOLDER_PREFIX must not be empty")
BASE_PREFIX = BASE_PREFIX + "/"  # e.g. "gallery/"


# =============================================================================
# AWS clients / globals
# =============================================================================
_sm = boto3.client("secretsmanager")
_s3 = boto3.client("s3")
_private_key_obj = None


# =============================================================================
# Helpers: CloudFront-safe base64 + signing
# =============================================================================
def _cloudfront_url_safe_b64(data: bytes) -> str:
    s = base64.b64encode(data).decode("utf-8")
    return s.replace("+", "-").replace("=", "_").replace("/", "~")


def _load_private_key() -> Any:
    global _private_key_obj
    if _private_key_obj is not None:
        return _private_key_obj

    try:
        resp = _sm.get_secret_value(SecretId=PRIVATE_KEY_SECRET_ARN)
    except ClientError as e:
        raise RuntimeError(f"Failed to read secret {PRIVATE_KEY_SECRET_ARN}: {e}") from e

    pem = resp.get("SecretString")
    if not pem:
        pem = base64.b64decode(resp["SecretBinary"]).decode("utf-8")

    key = serialization.load_pem_private_key(pem.encode("utf-8"), password=None)
    _private_key_obj = key
    return key


def _build_custom_policy(resource_url_pattern: str, expires_epoch: int) -> str:
    policy = {
        "Statement": [
            {
                "Resource": resource_url_pattern,
                "Condition": {"DateLessThan": {"AWS:EpochTime": expires_epoch}},
            }
        ]
    }
    return json.dumps(policy, separators=(",", ":"))


def _sign_policy(policy_str: str) -> Tuple[str, str]:
    key = _load_private_key()
    policy_bytes = policy_str.encode("utf-8")
    signature = key.sign(policy_bytes, padding.PKCS1v15(), hashes.SHA1())
    policy_b64 = _cloudfront_url_safe_b64(policy_bytes)
    sig_b64 = _cloudfront_url_safe_b64(signature)
    return policy_b64, sig_b64


# =============================================================================
# Helpers: error redirects (for /open only)
# =============================================================================
def _redirect_error(http_code: int, reason: str) -> Dict[str, Any]:
    location = (
        f"https://{CLOUDFRONT_DOMAIN}{ERROR_PAGE_PATH}"
        f"?code={quote(str(http_code), safe='')}"
        f"&reason={quote(reason, safe='')}"
    )
    return {
        "statusCode": 302,
        "headers": {"Location": location, "Cache-Control": "no-store", "Pragma": "no-cache"},
        "body": "",
    }


# =============================================================================
# Helpers: short stateless share token (binary payload + truncated HMAC)
# =============================================================================
_TOKEN_VER = 1
_HMAC_TRUNC_BYTES = 12  # 12 bytes = 96-bit tag (~16 base64url chars)

def _b64url(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).decode("utf-8").rstrip("=")

def _b64url_decode(s: str) -> bytes:
    s += "=" * (-len(s) % 4)
    return base64.urlsafe_b64decode(s.encode("utf-8"))

def _make_share_token(folder_param: str, cookie_ttl_seconds: int, link_exp: int) -> str:
    # payload = [ver:1][exp:4][ttl:4][folder:N]
    folder_bytes = folder_param.encode("utf-8")
    payload = struct.pack(">BII", _TOKEN_VER, int(link_exp), int(cookie_ttl_seconds)) + folder_bytes
    mac = hmac.new(LINK_SIGNING_SECRET, payload, hashlib.sha256).digest()[:_HMAC_TRUNC_BYTES]
    return f"{_b64url(payload)}.{_b64url(mac)}"

def _verify_share_token(token: str) -> Dict[str, Any]:
    try:
        b, s = token.split(".", 1)
        payload = _b64url_decode(b)
        mac = _b64url_decode(s)
    except Exception:
        raise ValueError("invalid_token_format")

    expected = hmac.new(LINK_SIGNING_SECRET, payload, hashlib.sha256).digest()[:_HMAC_TRUNC_BYTES]
    if not hmac.compare_digest(expected, mac):
        raise ValueError("invalid_token_signature")

    if len(payload) < 9:
        raise ValueError("invalid_token_payload")

    ver, link_exp, cookie_ttl_seconds = struct.unpack(">BII", payload[:9])
    if ver != _TOKEN_VER:
        raise ValueError("unsupported_token_version")

    folder_param = payload[9:].decode("utf-8", errors="strict")

    return {
        "folder": folder_param,
        "cookie_ttl_seconds": int(cookie_ttl_seconds),
        "link_exp": int(link_exp),
    }


# =============================================================================
# Helpers: request parsing / validation
# =============================================================================
def _normalize_folder(folder: str) -> str:
    s = (folder or "").strip()
    if not s:
        raise ValueError("folder_required")

    s = s.lstrip("/").rstrip("/")
    if not s:
        raise ValueError("folder_required")

    if ".." in s or "//" in s:
        raise ValueError("invalid_folder_path")

    # Prevent accidental double-prefix
    if s.startswith(BASE_PREFIX) or s.startswith(BASE_PREFIX.rstrip("/")):
        raise ValueError("folder_must_not_include_base_prefix")

    if not re.fullmatch(r"[A-Za-z0-9._-]+(?:/[A-Za-z0-9._-]+)*", s):
        raise ValueError("invalid_folder_characters")

    return f"/{s}/"


def _parse_json_body(event: Dict[str, Any]) -> Dict[str, Any]:
    body = event.get("body")
    if not body:
        return {}
    try:
        if event.get("isBase64Encoded"):
            body = base64.b64decode(body).decode("utf-8")
        return json.loads(body)
    except Exception:
        return {}


def _parse_link_ttl_seconds_from_admin_request(event: Dict[str, Any]) -> int:
    link_ttl = None
    q = event.get("queryStringParameters") or {}
    if "link_ttl_seconds" in q:
        link_ttl = q.get("link_ttl_seconds")

    payload = _parse_json_body(event)
    if link_ttl is None:
        link_ttl = payload.get("link_ttl_seconds")

    link_ttl_seconds = DEFAULT_LINK_TTL_SECONDS if link_ttl is None else int(link_ttl)
    if link_ttl_seconds < 60:
        raise ValueError("link_ttl_seconds_must_be_ge_60")
    return link_ttl_seconds


def _parse_folder_from_admin_request(event: Dict[str, Any]) -> str:
    folder = None
    q = event.get("queryStringParameters") or {}
    if "folder" in q:
        folder = q["folder"]

    payload = _parse_json_body(event)
    if folder is None:
        folder = payload.get("folder") or payload.get("path")

    if folder is None:
        raise ValueError("folder_required")

    return _normalize_folder(folder)


def _request_method(event: Dict[str, Any]) -> str:
    m = (event.get("requestContext") or {}).get("http", {}).get("method")
    if m:
        return m.upper()
    m = event.get("httpMethod")
    if m:
        return m.upper()
    return "GET"


def _request_path(event: Dict[str, Any]) -> str:
    p = event.get("rawPath")
    if p:
        return p
    p = event.get("path")
    if p:
        return p
    return "/"


# =============================================================================
# Helpers: response building
# =============================================================================
def _cookie_attrs(max_age: Optional[int]) -> str:
    parts = [f"Path={COOKIE_PATH}"]

    if COOKIE_DOMAIN:
        parts.append(f"Domain={COOKIE_DOMAIN}")
    if COOKIE_SECURE:
        parts.append("Secure")
    if COOKIE_HTTPONLY:
        parts.append("HttpOnly")

    parts.append(f"SameSite={COOKIE_SAMESITE}")

    if max_age is not None:
        parts.append(f"Max-Age={max_age}")

    return "; ".join(parts)


def _response_redirect(location: str, cookies: Dict[str, str], max_age: Optional[int]) -> Dict[str, Any]:
    cookie_strings = []
    attrs = _cookie_attrs(max_age)

    for k, v in cookies.items():
        cookie_strings.append(f"{k}={v}; {attrs}")

    return {
        "statusCode": 302,
        "headers": {"Location": location, "Cache-Control": "no-store", "Pragma": "no-cache"},
        "cookies": cookie_strings,
        "multiValueHeaders": {"Set-Cookie": cookie_strings},
        "body": "",
    }


def _response_json(status: int, payload: Dict[str, Any]) -> Dict[str, Any]:
    return {
        "statusCode": status,
        "headers": {"Content-Type": "application/json", "Cache-Control": "no-store"},
        "body": json.dumps(payload),
    }


# =============================================================================
# Helpers: list images + zip from S3
# =============================================================================
def _is_allowed_image_key(key: str) -> bool:
    lk = key.lower()
    return any(lk.endswith(ext) for ext in ALLOWED_IMAGE_EXT)

def _is_allowed_zip_key(key: str) -> bool:
    lk = key.lower()
    return any(lk.endswith(ext) for ext in ALLOWED_ZIP_EXT)

def _list_folder_for_prefix(prefix: str) -> Tuple[List[str], Optional[str]]:
    image_keys: List[str] = []
    zip_best_key: Optional[str] = None
    zip_best_last_modified = None

    token: Optional[str] = None
    while True:
        args = {"Bucket": GALLERY_BUCKET, "Prefix": prefix, "MaxKeys": 1000}
        if token:
            args["ContinuationToken"] = token

        resp = _s3.list_objects_v2(**args)

        for obj in resp.get("Contents", []):
            k = obj.get("Key", "")
            if not k or k.endswith("/"):
                continue

            if _is_allowed_image_key(k):
                image_keys.append(k)

            if _is_allowed_zip_key(k):
                lm = obj.get("LastModified")
                if zip_best_last_modified is None or (lm and lm > zip_best_last_modified):
                    zip_best_last_modified = lm
                    zip_best_key = k

        if not resp.get("IsTruncated"):
            break

        token = resp.get("NextContinuationToken")

    if len(image_keys) > MAX_LIST_KEYS:
        image_keys = image_keys[:MAX_LIST_KEYS]

    return image_keys, zip_best_key


# =============================================================================
# Lambda handler
# =============================================================================
def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    method = _request_method(event)
    path = _request_path(event)

    # Decide error style:
    # - /open => redirect to error.html (human-facing)
    # - /list, /sign => JSON (fetch-facing)
    wants_redirect = path.endswith(OPEN_PATH)

    try:
        # ---------------------------------------------------------------------
        # 1) Admin endpoint: POST /sign -> returns share_url (JSON)
        # ---------------------------------------------------------------------
        if method == "POST" and path.endswith(SIGN_PATH):
            folder = _parse_folder_from_admin_request(event)  # "/client123/job456/"

            # cookies fixed at 24h (86400)
            cookie_ttl_seconds = 86400

            # link TTL optional
            link_ttl_seconds = _parse_link_ttl_seconds_from_admin_request(event)

            folder_param = folder.lstrip("/")  # "client123/job456/"
            now = int(time.time())
            link_exp = now + link_ttl_seconds

            share_token = _make_share_token(folder_param, cookie_ttl_seconds, link_exp)
            share_url = f"https://{CLOUDFRONT_DOMAIN}{OPEN_PATH}?t={share_token}"
            return _response_json(200, {"share_url": share_url})

        # ---------------------------------------------------------------------
        # 2) GET/HEAD /list?folder=... -> list image keys + newest zip key (JSON)
        # ---------------------------------------------------------------------
        if method in ("GET", "HEAD") and path.endswith(LIST_PATH):
            folder = None
            q = event.get("queryStringParameters") or {}
            if "folder" in q:
                folder = q["folder"]
            if folder is None:
                payload = _parse_json_body(event)
                folder = payload.get("folder") or payload.get("path")
            if folder is None:
                raise ValueError("folder_required")

            folder_norm = _normalize_folder(folder)                   # "/client123/job456/"
            prefix = BASE_PREFIX + folder_norm.lstrip("/")            # "gallery/client123/job456/"

            files, zip_key = _list_folder_for_prefix(prefix)

            if method == "HEAD":
                return {"statusCode": 200, "headers": {"Cache-Control": "no-store"}, "body": ""}

            out = {"folder": prefix, "files": files}
            if zip_key:
                out["zip"] = zip_key
            return _response_json(200, out)

        # ---------------------------------------------------------------------
        # 3) Public endpoint: GET/HEAD /open?t=... -> set cookies + redirect (HUMAN)
        # ---------------------------------------------------------------------
        if method not in ("GET", "HEAD"):
            # human-friendly for /open, json for others
            if wants_redirect:
                return _redirect_error(405, "method_not_allowed")
            return _response_json(405, {"error": "method_not_allowed"})

        if not path.endswith(OPEN_PATH):
            return _response_json(404, {"error": "not_found"})

        q = event.get("queryStringParameters") or {}
        token = q.get("t")
        if not token:
            mv = event.get("multiValueQueryStringParameters") or {}
            tlist = mv.get("t")
            if tlist:
                token = tlist[0]
        if not token:
            return _redirect_error(400, "missing_token")

        try:
            payload = _verify_share_token(token)
        except ValueError:
            return _redirect_error(403, "invalid_link")

        folder_param = payload.get("folder")
        if not isinstance(folder_param, str) or not folder_param.strip():
            return _redirect_error(400, "bad_request")

        cookie_ttl_seconds = int(payload.get("cookie_ttl_seconds", DEFAULT_TTL_SECONDS))
        if cookie_ttl_seconds < 60:
            cookie_ttl_seconds = 60
        cookie_ttl_seconds = min(cookie_ttl_seconds, MAX_TTL_SECONDS)

        link_exp = int(payload.get("link_exp", 0))
        now = int(time.time())
        if link_exp and now > link_exp:
            return _redirect_error(403, "link_expired")

        # Validate folder and build prefix
        try:
            folder_norm = _normalize_folder(folder_param)                 # "/client123/job456/"
        except ValueError:
            return _redirect_error(400, "bad_request")

        folder_no_slash = folder_norm.lstrip("/")                         # "client123/job456/"

        expires_epoch = now + cookie_ttl_seconds

        resource_pattern = f"https://{CLOUDFRONT_DOMAIN}/{BASE_PREFIX}{folder_no_slash}*"
        policy_str = _build_custom_policy(resource_pattern, expires_epoch)
        policy_b64, sig_b64 = _sign_policy(policy_str)

        cookies = {
            "CloudFront-Policy": policy_b64,
            "CloudFront-Signature": sig_b64,
            "CloudFront-Key-Pair-Id": CLOUDFRONT_KEY_PAIR_ID,
        }

        location = (
            f"https://{CLOUDFRONT_DOMAIN}{GALLERY_INDEX_PATH}"
            f"?folder={quote(folder_no_slash, safe='')}"
        )

        max_age = cookie_ttl_seconds if COOKIE_SET_MAX_AGE else None
        return _response_redirect(location, cookies, max_age)

    except ValueError as ve:
        # for /list or /sign: JSON
        if wants_redirect:
            return _redirect_error(400, "bad_request")
        return _response_json(400, {"error": str(ve)})

    except Exception as e:
        print("UNHANDLED_EXCEPTION:", repr(e))
        if wants_redirect:
            return _redirect_error(500, "internal_error")
        return _response_json(500, {"error": "internal_error", "detail": str(e)})
