import os
import json
import time
import base64
import re
from typing import Any, Dict, Optional, Tuple
from urllib.parse import quote

import boto3
from botocore.exceptions import ClientError

from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import padding


# -----------------------------
# Config
# -----------------------------
CLOUDFRONT_DOMAIN = os.environ["CLOUDFRONT_DOMAIN"].strip()  # gallery.project-practice.com
CLOUDFRONT_KEY_PAIR_ID = os.environ["CLOUDFRONT_KEY_PAIR_ID"].strip()
PRIVATE_KEY_SECRET_ARN = os.environ["CLOUDFRONT_PRIVATE_KEY_SECRET_ARN"].strip()

# OPTIONAL restriction: "" means allow any root folder "client123/..."
ALLOWED_PREFIX = os.getenv("ALLOWED_FOLDER_PREFIX", "").strip().lstrip("/")

DEFAULT_TTL_SECONDS = int(os.getenv("DEFAULT_TTL_SECONDS", "604800"))  # 7 days
MAX_TTL_SECONDS = int(os.getenv("MAX_TTL_SECONDS", "1209600"))         # 14 days

COOKIE_SECURE = os.getenv("COOKIE_SECURE", "true").lower() == "true"
COOKIE_HTTPONLY = os.getenv("COOKIE_HTTPONLY", "true").lower() == "true"
COOKIE_SAMESITE = os.getenv("COOKIE_SAMESITE", "Lax")  # Lax/Strict/None
COOKIE_SET_MAX_AGE = os.getenv("COOKIE_SET_MAX_AGE", "false").lower() == "true"

COOKIE_DOMAIN = os.getenv("COOKIE_DOMAIN", CLOUDFRONT_DOMAIN).strip()
COOKIE_PATH = os.getenv("COOKIE_PATH", "/").strip()

# /open is served on the GALLERY domain via CloudFront behavior -> API origin
OPEN_PATH = os.getenv("OPEN_PATH", "/open").strip()

# Single app at bucket root
GALLERY_INDEX_PATH = os.getenv("GALLERY_INDEX_PATH", "/index.html").strip()


# -----------------------------
# Globals
# -----------------------------
_sm = boto3.client("secretsmanager")
_private_key_obj = None


# -----------------------------
# Helpers
# -----------------------------
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


def _normalize_folder(folder: str) -> str:
    """
    Accepts: "client123", "client123/job456", "/client123/job456/"
    Returns: "/client123/" or "/client123/job456/"
    """
    s = (folder or "").strip()
    if not s:
        raise ValueError("folder is required")

    s = s.lstrip("/").rstrip("/")
    if not s:
        raise ValueError("folder is required")

    if ".." in s or "//" in s:
        raise ValueError("invalid folder path")

    if ALLOWED_PREFIX:
        allowed = ALLOWED_PREFIX.rstrip("/") + "/"
        if not (s + "/").startswith(allowed):
            raise ValueError(f"folder must start with '{allowed}'")

    if not re.fullmatch(r"[A-Za-z0-9._-]+(?:/[A-Za-z0-9._-]+)*", s):
        raise ValueError("folder contains invalid characters")

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


def _parse_ttl_seconds(event: Dict[str, Any]) -> int:
    ttl = None

    q = event.get("queryStringParameters") or {}
    if "cookie_retention_seconds" in q:
        ttl = q.get("cookie_retention_seconds")
    elif "cookie_retention" in q:
        ttl = q.get("cookie_retention")

    if ttl is None and event.get("multiValueQueryStringParameters"):
        mv = event["multiValueQueryStringParameters"]
        if "cookie_retention_seconds" in mv and mv["cookie_retention_seconds"]:
            ttl = mv["cookie_retention_seconds"][0]

    payload = _parse_json_body(event)
    if ttl is None:
        ttl = payload.get("cookie_retention_seconds") or payload.get("cookie_retention")

    ttl_seconds = DEFAULT_TTL_SECONDS if ttl is None else int(ttl)

    if ttl_seconds < 60:
        raise ValueError("cookie_retention_seconds must be >= 60 seconds")

    return min(ttl_seconds, MAX_TTL_SECONDS)


def _parse_folder(event: Dict[str, Any]) -> str:
    folder = None

    q = event.get("queryStringParameters") or {}
    if "folder" in q:
        folder = q["folder"]

    if folder is None:
        payload = _parse_json_body(event)
        folder = payload.get("folder") or payload.get("path")

    if folder is None:
        raise ValueError("folder parameter is required")

    return _normalize_folder(folder)


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
        "headers": {
            "Location": location,
            "Cache-Control": "no-store",
            "Pragma": "no-cache",
        },
        "cookies": cookie_strings,                 # HTTP API v2
        "multiValueHeaders": {"Set-Cookie": cookie_strings},  # REST API
        "body": "",
    }


def _response_json(status: int, payload: Dict[str, Any]) -> Dict[str, Any]:
    return {
        "statusCode": status,
        "headers": {"Content-Type": "application/json", "Cache-Control": "no-store"},
        "body": json.dumps(payload),
    }


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


# -----------------------------
# Lambda handler
# -----------------------------
def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    try:
        method = _request_method(event)
        path = _request_path(event)

        # 1) POST /sign -> returns share_url on the GALLERY domain (not execute-api)
        if method == "POST" and path.endswith("/sign"):
            folder = _parse_folder(event)              # "/client123/job456/"
            ttl_seconds = _parse_ttl_seconds(event)

            folder_param = folder.lstrip("/")          # "client123/job456/"
            share_url = (
                f"https://{CLOUDFRONT_DOMAIN}{OPEN_PATH}"
                f"?folder={quote(folder_param, safe='')}"
                f"&cookie_retention_seconds={ttl_seconds}"
            )

            return _response_json(200, {"share_url": share_url})

        # 2) Only allow cookie minting on GET/HEAD /open
        if method not in ("GET", "HEAD"):
            return _response_json(405, {"error": "method_not_allowed"})

        if not path.endswith(OPEN_PATH):
            return _response_json(404, {"error": "not_found"})

        folder = _parse_folder(event)
        ttl_seconds = _parse_ttl_seconds(event)

        now = int(time.time())
        expires_epoch = now + ttl_seconds

        # Scope access to this folder only
        resource_pattern = f"https://{CLOUDFRONT_DOMAIN}{folder}*"
        policy_str = _build_custom_policy(resource_pattern, expires_epoch)
        policy_b64, sig_b64 = _sign_policy(policy_str)

        cookies = {
            "CloudFront-Policy": policy_b64,
            "CloudFront-Signature": sig_b64,
            "CloudFront-Key-Pair-Id": CLOUDFRONT_KEY_PAIR_ID,
        }

        # Redirect to ONE root app page
        folder_param = folder.lstrip("/")  # "client123/job456/"
        location = f"https://{CLOUDFRONT_DOMAIN}{GALLERY_INDEX_PATH}?folder={quote(folder_param, safe='')}"

        max_age = ttl_seconds if COOKIE_SET_MAX_AGE else None
        return _response_redirect(location, cookies, max_age)

    except ValueError as ve:
        return _response_json(400, {"error": str(ve)})
    except Exception as e:
        print("UNHANDLED_EXCEPTION:", repr(e))
        return _response_json(500, {"error": "internal_error", "detail": str(e)})