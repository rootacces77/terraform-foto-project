"""
Lambda: CloudFront signed-cookie "share" endpoint

Purpose
- Accepts parameters:
  - folder: e.g. "/clients/client123/job456/" (or "clients/client123/job456/")
  - cookie_retention_seconds: e.g. 604800 (7 days)
- Returns:
  - 302 redirect to the gallery URL
  - Set-Cookie headers:
      CloudFront-Policy, CloudFront-Signature, CloudFront-Key-Pair-Id

Dependencies
- Requires the "cryptography" package.
  Easiest: add it via a Lambda Layer (or package it into the deployment artifact).

Environment Variables (required)
- CLOUDFRONT_DOMAIN                 e.g. "photos.example.com"
- CLOUDFRONT_KEY_PAIR_ID            e.g. "K1234567890ABCDE"
- CLOUDFRONT_PRIVATE_KEY_SECRET_ARN Secrets Manager secret ARN containing the PEM private key
                                   (secret value is the PEM text)
Environment Variables (recommended)
- ALLOWED_FOLDER_PREFIX             default: "/clients/"
- DEFAULT_TTL_SECONDS               default: 604800  (7 days)
- MAX_TTL_SECONDS                   default: 1209600 (14 days)
- REDIRECT_TO_INDEX                 default: "true"  (redirect to /index.html)
- COOKIE_SECURE                     default: "true"
- COOKIE_HTTPONLY                   default: "true"
- COOKIE_SAMESITE                   default: "Lax"   (use "None" if you need cross-site)
"""

import os
import json
import time
import base64
import re
from typing import Any, Dict, Optional, Tuple

import boto3
from botocore.exceptions import ClientError

from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import padding


# -----------------------------
# Config
# -----------------------------
CLOUDFRONT_DOMAIN = os.environ["CLOUDFRONT_DOMAIN"].strip()
CLOUDFRONT_KEY_PAIR_ID = os.environ["CLOUDFRONT_KEY_PAIR_ID"].strip()
PRIVATE_KEY_SECRET_ARN = os.environ["CLOUDFRONT_PRIVATE_KEY_SECRET_ARN"].strip()

ALLOWED_PREFIX = os.getenv("ALLOWED_FOLDER_PREFIX", "/clients/").strip()
DEFAULT_TTL_SECONDS = int(os.getenv("DEFAULT_TTL_SECONDS", "604800"))  # 7 days
MAX_TTL_SECONDS = int(os.getenv("MAX_TTL_SECONDS", "1209600"))         # 14 days
REDIRECT_TO_INDEX = os.getenv("REDIRECT_TO_INDEX", "true").lower() == "true"

COOKIE_SECURE = os.getenv("COOKIE_SECURE", "true").lower() == "true"
COOKIE_HTTPONLY = os.getenv("COOKIE_HTTPONLY", "true").lower() == "true"
COOKIE_SAMESITE = os.getenv("COOKIE_SAMESITE", "Lax")  # Lax/Strict/None

# For small admin tools you usually want session cookies (no explicit Max-Age).
# If you want cookies to persist in the browser for the same TTL, set:
COOKIE_SET_MAX_AGE = os.getenv("COOKIE_SET_MAX_AGE", "false").lower() == "true"

# Optional: domain for cookies (usually your CloudFront domain)
COOKIE_DOMAIN = os.getenv("COOKIE_DOMAIN", CLOUDFRONT_DOMAIN).strip()

# Optional: restrict cookie path. "/" is simplest.
COOKIE_PATH = os.getenv("COOKIE_PATH", "/").strip()


# -----------------------------
# Globals (cached across invocations)
# -----------------------------
_sm = boto3.client("secretsmanager")
_private_key_obj = None


# -----------------------------
# Helpers
# -----------------------------
def _cloudfront_url_safe_b64(data: bytes) -> str:
    """
    CloudFront uses a URL-safe variant:
      '+' -> '-'
      '=' -> '_'
      '/' -> '~'
    """
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
        # If stored as binary
        pem = base64.b64decode(resp["SecretBinary"]).decode("utf-8")

    key = serialization.load_pem_private_key(
        pem.encode("utf-8"),
        password=None,
    )
    _private_key_obj = key
    return key


def _normalize_folder(folder: str) -> str:
    folder = folder.strip()
    if not folder:
        raise ValueError("folder is required")

    # Ensure it starts with "/"
    if not folder.startswith("/"):
        folder = "/" + folder

    # Ensure it ends with "/"
    if not folder.endswith("/"):
        folder = folder + "/"

    # Basic traversal / invalid pattern prevention
    if ".." in folder or "//" in folder:
        raise ValueError("invalid folder path")

    # Restrict to allowed prefix
    if not folder.startswith(ALLOWED_PREFIX):
        raise ValueError(f"folder must start with {ALLOWED_PREFIX}")

    # Conservative allowlist: letters, numbers, dash, underscore, slash
    if not re.fullmatch(r"[/A-Za-z0-9._-]+/", folder):
        raise ValueError("folder contains invalid characters")

    return folder


def _parse_ttl_seconds(event: Dict[str, Any]) -> int:
    """
    Accepts cookie_retention_seconds as query param or JSON field.
    Falls back to DEFAULT_TTL_SECONDS, clamps to MAX_TTL_SECONDS.
    """
    ttl = None

    # HTTP API v2 query params
    q = (event.get("queryStringParameters") or {}) if isinstance(event, dict) else {}
    if q:
        if "cookie_retention_seconds" in q:
            ttl = q.get("cookie_retention_seconds")
        elif "cookie_retention" in q:
            ttl = q.get("cookie_retention")

    # REST API query params (same key)
    if ttl is None and event.get("multiValueQueryStringParameters"):
        mv = event["multiValueQueryStringParameters"]
        if "cookie_retention_seconds" in mv and mv["cookie_retention_seconds"]:
            ttl = mv["cookie_retention_seconds"][0]

    # JSON body
    if ttl is None and event.get("body"):
        try:
            body = event["body"]
            if event.get("isBase64Encoded"):
                body = base64.b64decode(body).decode("utf-8")
            payload = json.loads(body)
            ttl = payload.get("cookie_retention_seconds") or payload.get("cookie_retention")
        except Exception:
            ttl = None

    if ttl is None:
        ttl_seconds = DEFAULT_TTL_SECONDS
    else:
        ttl_seconds = int(ttl)

    if ttl_seconds < 60:
        raise ValueError("cookie_retention_seconds must be >= 60 seconds")

    return min(ttl_seconds, MAX_TTL_SECONDS)


def _parse_folder(event: Dict[str, Any]) -> str:
    folder = None

    q = (event.get("queryStringParameters") or {}) if isinstance(event, dict) else {}
    if q and "folder" in q:
        folder = q["folder"]

    if folder is None and event.get("body"):
        try:
            body = event["body"]
            if event.get("isBase64Encoded"):
                body = base64.b64decode(body).decode("utf-8")
            payload = json.loads(body)
            folder = payload.get("folder") or payload.get("path")
        except Exception:
            folder = None

    if folder is None:
        raise ValueError("folder parameter is required")

    return _normalize_folder(folder)


def _build_custom_policy(resource_url_pattern: str, expires_epoch: int) -> str:
    """
    Custom policy restricting access to a resource pattern until a specific epoch time.
    """
    policy = {
        "Statement": [
            {
                "Resource": resource_url_pattern,
                "Condition": {
                    "DateLessThan": {"AWS:EpochTime": expires_epoch}
                }
            }
        ]
    }
    return json.dumps(policy, separators=(",", ":"))


def _sign_policy(policy_str: str) -> Tuple[str, str]:
    """
    Returns (policy_b64_cf, signature_b64_cf)
    """
    key = _load_private_key()

    policy_bytes = policy_str.encode("utf-8")

    # CloudFront signed cookies traditionally use RSA-SHA1 with PKCS#1 v1.5 padding.
    signature = key.sign(
        policy_bytes,
        padding.PKCS1v15(),
        hashes.SHA1()
    )

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

    # SameSite
    # If SameSite=None, Secure must be true (most browsers)
    parts.append(f"SameSite={COOKIE_SAMESITE}")

    if max_age is not None:
        parts.append(f"Max-Age={max_age}")

    return "; ".join(parts)


def _response_redirect(location: str, cookies: Dict[str, str], max_age: Optional[int]) -> Dict[str, Any]:
    # API Gateway supports multiple Set-Cookie headers in different ways:
    # - HTTP API v2: use "cookies": [...]
    # - REST API: use "multiValueHeaders": {"Set-Cookie": [...]}
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
        # HTTP API v2 uses "cookies"
        "cookies": cookie_strings,
        "body": ""
    }


# -----------------------------
# Lambda handler
# -----------------------------
def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    try:
        folder = _parse_folder(event)
        ttl_seconds = _parse_ttl_seconds(event)

        now = int(time.time())
        expires_epoch = now + ttl_seconds

        # Scope the cookie to this folder only
        # Use https scheme + CloudFront domain
        # Note: include wildcard for all objects under folder.
        resource_pattern = f"https://{CLOUDFRONT_DOMAIN}{folder}*"

        policy_str = _build_custom_policy(resource_pattern, expires_epoch)
        policy_b64, sig_b64 = _sign_policy(policy_str)

        # Cookies required by CloudFront for custom policy
        cookies = {
            "CloudFront-Policy": policy_b64,
            "CloudFront-Signature": sig_b64,
            "CloudFront-Key-Pair-Id": CLOUDFRONT_KEY_PAIR_ID,
        }

        # Redirect target
        if REDIRECT_TO_INDEX:
            location = f"https://{CLOUDFRONT_DOMAIN}{folder}index.html"
        else:
            location = f"https://{CLOUDFRONT_DOMAIN}{folder}"

        max_age = ttl_seconds if COOKIE_SET_MAX_AGE else None
        return _response_redirect(location, cookies, max_age)

    except ValueError as ve:
        return {
            "statusCode": 400,
            "headers": {"Content-Type": "application/json"},
            "body": json.dumps({"error": str(ve)}),
        }
    except Exception as e:
        # Avoid leaking internals
        return {
            "statusCode": 500,
            "headers": {"Content-Type": "application/json"},
            "body": json.dumps({"error": "internal_error"}),
        }