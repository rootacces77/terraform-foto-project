import os
import json
import time
import base64
import re
import secrets
from typing import Any, Dict, Optional, Tuple, List
from urllib.parse import quote

import boto3
from botocore.exceptions import ClientError

from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import padding


# =============================================================================
# Config (env vars)
# =============================================================================
CLOUDFRONT_DOMAIN = os.environ["CLOUDFRONT_DOMAIN"].strip()
CLOUDFRONT_KEY_PAIR_ID = os.environ["CLOUDFRONT_KEY_PAIR_ID"].strip()
PRIVATE_KEY_SECRET_ARN = os.environ["CLOUDFRONT_PRIVATE_KEY_SECRET_ARN"].strip()
GALLERY_BUCKET = os.environ["GALLERY_BUCKET"].strip()
DDB_TABLE_NAME = os.environ["DDB_TABLE_NAME"].strip()

ALLOWED_PREFIX_RAW = os.getenv("ALLOWED_FOLDER_PREFIX", "").strip().lstrip("/")
if not ALLOWED_PREFIX_RAW:
    raise RuntimeError("ALLOWED_FOLDER_PREFIX must not be empty")

# NEW: thumbs root prefix (must end with "/")
THUMBS_PREFIX = os.getenv("THUMBS_PREFIX", "thumbs/").strip().strip("/") + "/"  # e.g. "thumbs/"

DEFAULT_TTL_SECONDS = int(os.getenv("DEFAULT_TTL_SECONDS", "86400"))
MAX_TTL_SECONDS = int(os.getenv("MAX_TTL_SECONDS", "86400"))

DEFAULT_LINK_TTL_SECONDS = int(os.getenv("DEFAULT_LINK_TTL_SECONDS", str(7 * 24 * 3600)))

TOKEN_TTL_BUFFER_SECONDS = int(os.getenv("TOKEN_TTL_BUFFER_SECONDS", "86400"))  # keep token item longer than link_exp
LIST_CACHE_TTL_SECONDS = int(os.getenv("LIST_CACHE_TTL_SECONDS", "300"))        # 5 min

ERROR_PAGE_PATH = os.getenv("ERROR_PAGE_PATH", "/site/error.html").strip()
GALLERY_INDEX_PATH = os.getenv("GALLERY_INDEX_PATH", "/site/index.html").strip()

OPEN_PATH = os.getenv("OPEN_PATH", "/open").strip()
LIST_PATH = os.getenv("LIST_PATH", "/list").strip()
SIGN_PATH = os.getenv("SIGN_PATH", "/sign").strip()
REVOKE_PATH = os.getenv("REVOKE_PATH", "/revoke").strip()
ADMIN_LINKS_PATH = os.getenv("ADMIN_LINKS_PATH", "/admin/links").strip()

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

# Cookie attributes
COOKIE_SECURE = os.getenv("COOKIE_SECURE", "true").lower() == "true"
COOKIE_HTTPONLY = os.getenv("COOKIE_HTTPONLY", "true").lower() == "true"
COOKIE_SAMESITE = os.getenv("COOKIE_SAMESITE", "None")
COOKIE_SET_MAX_AGE = os.getenv("COOKIE_SET_MAX_AGE", "true").lower() == "true"
COOKIE_DOMAIN = os.getenv("COOKIE_DOMAIN", CLOUDFRONT_DOMAIN).strip()
COOKIE_PATH = os.getenv("COOKIE_PATH", "/").strip()

# Whether /open redirect should include ?t=token for the gallery JS to call /list securely.
INCLUDE_TOKEN_IN_REDIRECT = os.getenv("INCLUDE_TOKEN_IN_REDIRECT", "true").lower() == "true"

# Normalize base prefix once (must end with "/")
BASE_PREFIX = ALLOWED_PREFIX_RAW.strip().strip("/") + "/"  # e.g. "gallery/"


# =============================================================================
# AWS clients
# =============================================================================
_sm = boto3.client("secretsmanager")
_s3 = boto3.client("s3")

_ddb = boto3.resource("dynamodb")
_table = _ddb.Table(DDB_TABLE_NAME)

_private_key_obj = None


# =============================================================================
# Helpers: request method/path
# =============================================================================
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


# NEW: policy includes BOTH gallery + thumbs
def _build_custom_policy_for_folder(folder: str, expires_epoch: int) -> str:
    """
    folder is normalized like "client/job/".
    Allows access to:
      - /gallery/<folder>* (BASE_PREFIX)
      - /thumbs/<folder>*  (THUMBS_PREFIX)
    """
    resources = [
        f"https://{CLOUDFRONT_DOMAIN}/{BASE_PREFIX}{folder}*",
        f"https://{CLOUDFRONT_DOMAIN}/{THUMBS_PREFIX}{folder}*",
    ]
    policy = {
        "Statement": [
            {
                "Resource": r,
                "Condition": {"DateLessThan": {"AWS:EpochTime": int(expires_epoch)}},
            }
            for r in resources
        ]
    }
    return json.dumps(policy, separators=(",", ":"))


def _sign_policy(policy_str: str) -> Tuple[str, str]:
    key = _load_private_key()
    policy_bytes = policy_str.encode("utf-8")
    signature = key.sign(policy_bytes, padding.PKCS1v15(), hashes.SHA1())
    return _cloudfront_url_safe_b64(policy_bytes), _cloudfront_url_safe_b64(signature)


# =============================================================================
# Helpers: parsing / validation
# =============================================================================
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

    return f"{s}/"  # always "client/job/"


def _parse_folder_from_admin_request(event: Dict[str, Any]) -> str:
    q = event.get("queryStringParameters") or {}
    folder = q.get("folder")
    payload = _parse_json_body(event)
    if folder is None:
        folder = payload.get("folder") or payload.get("path")
    if folder is None:
        raise ValueError("folder_required")
    return _normalize_folder(folder)


def _parse_link_ttl_seconds_from_admin_request(event: Dict[str, Any]) -> int:
    q = event.get("queryStringParameters") or {}
    link_ttl = q.get("link_ttl_seconds")
    payload = _parse_json_body(event)
    if link_ttl is None:
        link_ttl = payload.get("link_ttl_seconds")

    link_ttl_seconds = DEFAULT_LINK_TTL_SECONDS if link_ttl is None else int(link_ttl)
    if link_ttl_seconds < 60:
        raise ValueError("link_ttl_seconds_must_be_ge_60")
    return link_ttl_seconds


def _parse_token(event: Dict[str, Any]) -> Optional[str]:
    q = event.get("queryStringParameters") or {}
    token = q.get("t")

    if not token:
        mv = event.get("multiValueQueryStringParameters") or {}
        tlist = mv.get("t")
        if tlist:
            token = tlist[0]

    if not token:
        payload = _parse_json_body(event)
        token = payload.get("token") or payload.get("t")

    token = (token or "").strip()
    return token or None


# =============================================================================
# Helpers: responses
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
        parts.append(f"Max-Age={int(max_age)}")
    return "; ".join(parts)


def _response_json(status: int, payload: Dict[str, Any], cache_control: str = "no-store") -> Dict[str, Any]:
    return {
        "statusCode": status,
        "headers": {
            "Content-Type": "application/json",
            "Cache-Control": cache_control,
        },
        "body": json.dumps(payload),
    }


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
        "cookies": cookie_strings,
        "multiValueHeaders": {"Set-Cookie": cookie_strings},
        "body": "",
    }


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
# Helpers: S3 listing
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
# Helpers: DynamoDB token ops
# =============================================================================
def _new_token() -> str:
    return secrets.token_urlsafe(24)


def _ddb_get_token(token: str) -> Optional[Dict[str, Any]]:
    try:
        resp = _table.get_item(Key={"link_token": token}, ConsistentRead=True)
        return resp.get("Item")
    except Exception:
        return None


# =============================================================================
# Lambda handler
# =============================================================================
def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    method = _request_method(event)
    path = _request_path(event)

    wants_redirect = path.endswith(OPEN_PATH)

    try:
        # ---------------------------------------------------------------------
        # ADMIN: GET /admin/links
        # ---------------------------------------------------------------------
        if method == "GET" and path.endswith(ADMIN_LINKS_PATH):
            q = event.get("queryStringParameters") or {}
            limit = 200
            if "limit" in q:
                try:
                    limit = max(1, min(1000, int(q["limit"])))
                except Exception:
                    limit = 200

            now = int(time.time())
            items = []
            scanned = 0
            last_key = None

            while True:
                args = {"Limit": 200}
                if last_key:
                    args["ExclusiveStartKey"] = last_key

                resp = _table.scan(**args)
                scanned += int(resp.get("ScannedCount", 0) or 0)

                for it in resp.get("Items", []):
                    token = (it.get("link_token") or "").strip()
                    folder = (it.get("folder") or "").strip()
                    link_exp = int(it.get("link_exp", 0) or 0)
                    cookie_ttl = int(it.get("cookie_ttl_seconds", DEFAULT_TTL_SECONDS) or DEFAULT_TTL_SECONDS)

                    if not token:
                        continue
                    if link_exp and now > link_exp:
                        continue

                    items.append({
                        "token": token,
                        "folder": folder,
                        "link_exp": link_exp,
                        "cookie_ttl_seconds": cookie_ttl,
                    })

                    if len(items) >= limit:
                        break

                if len(items) >= limit:
                    break

                last_key = resp.get("LastEvaluatedKey")
                if not last_key:
                    break

            return _response_json(200, {"items": items, "returned": len(items), "scanned": scanned})

        # ---------------------------------------------------------------------
        # ADMIN: POST /sign
        # ---------------------------------------------------------------------
        if method == "POST" and path.endswith(SIGN_PATH):
            folder = _parse_folder_from_admin_request(event)
            link_ttl_seconds = _parse_link_ttl_seconds_from_admin_request(event)

            now = int(time.time())
            link_exp = now + int(link_ttl_seconds)

            cookie_ttl_seconds = min(DEFAULT_TTL_SECONDS, MAX_TTL_SECONDS)
            token = _new_token()

            ttl_epoch = int(link_exp) + int(TOKEN_TTL_BUFFER_SECONDS)

            item = {
                "link_token": token,
                "folder": folder,
                "link_exp": int(link_exp),
                "cookie_ttl_seconds": int(cookie_ttl_seconds),
                "created_epoch": int(now),
                "ttl_epoch": int(ttl_epoch),
            }

            _table.put_item(Item=item, ConditionExpression="attribute_not_exists(link_token)")

            share_url = f"https://{CLOUDFRONT_DOMAIN}{OPEN_PATH}?t={token}"
            return _response_json(200, {"share_url": share_url, "token": token})

        # ---------------------------------------------------------------------
        # ADMIN: POST /revoke
        # ---------------------------------------------------------------------
        if method == "POST" and path.endswith(REVOKE_PATH):
            token = _parse_token(event)
            if not token:
                return _response_json(400, {"error": "missing_token"})

            _table.delete_item(Key={"link_token": token})
            return _response_json(200, {"ok": True, "revoked": token})

        # ---------------------------------------------------------------------
        # PUBLIC: methods
        # ---------------------------------------------------------------------
        if method not in ("GET", "HEAD"):
            if wants_redirect:
                return _redirect_error(405, "method_not_allowed")
            return _response_json(405, {"error": "method_not_allowed"})

        # ---------------------------------------------------------------------
        # PUBLIC: GET /open?t=...
        # ---------------------------------------------------------------------
        if path.endswith(OPEN_PATH):
            token = _parse_token(event)
            if not token:
                return _redirect_error(400, "missing_token")

            item = _ddb_get_token(token)
            if not item:
                return _redirect_error(403, "invalid_link")

            now = int(time.time())
            link_exp = int(item.get("link_exp", 0) or 0)
            if link_exp and now > link_exp:
                return _redirect_error(403, "link_expired")

            folder = (item.get("folder") or "").strip()
            if not folder:
                return _redirect_error(400, "bad_request")

            cookie_ttl_seconds = int(item.get("cookie_ttl_seconds", DEFAULT_TTL_SECONDS) or DEFAULT_TTL_SECONDS)
            cookie_ttl_seconds = max(60, min(cookie_ttl_seconds, MAX_TTL_SECONDS))

            if link_exp:
                remaining = max(0, link_exp - now)
                if remaining < 60:
                    return _redirect_error(403, "link_expired")
                cookie_ttl_seconds = min(cookie_ttl_seconds, remaining)

            expires_epoch = now + cookie_ttl_seconds

            # NEW: signed policy covers BOTH gallery + thumbs for this folder
            policy_str = _build_custom_policy_for_folder(folder, expires_epoch)
            policy_b64, sig_b64 = _sign_policy(policy_str)

            cookies = {
                "CloudFront-Policy": policy_b64,
                "CloudFront-Signature": sig_b64,
                "CloudFront-Key-Pair-Id": CLOUDFRONT_KEY_PAIR_ID,
            }

            location = f"https://{CLOUDFRONT_DOMAIN}{GALLERY_INDEX_PATH}?folder={quote(folder, safe='')}"
            if INCLUDE_TOKEN_IN_REDIRECT:
                location += f"&t={quote(token, safe='')}"

            max_age = cookie_ttl_seconds if COOKIE_SET_MAX_AGE else None
            return _response_redirect(location, cookies, max_age)

        # ---------------------------------------------------------------------
        # PUBLIC: GET /list?folder=...&t=...
        # ---------------------------------------------------------------------
        if method in ("GET", "HEAD") and path.endswith(LIST_PATH):
            q = event.get("queryStringParameters") or {}
            folder_in = q.get("folder")
            if folder_in is None:
                payload = _parse_json_body(event)
                folder_in = payload.get("folder") or payload.get("path")

            if folder_in is None:
                return _response_json(400, {"error": "folder_required"})

            token = _parse_token(event)
            if not token:
                return _response_json(403, {"error": "missing_token"})

            item = _ddb_get_token(token)
            if not item:
                return _response_json(403, {"error": "invalid_link"})

            now = int(time.time())
            link_exp = int(item.get("link_exp", 0) or 0)
            if link_exp and now > link_exp:
                return _response_json(403, {"error": "link_expired"})

            req_folder = _normalize_folder(folder_in)
            token_folder = (item.get("folder") or "").strip()

            if req_folder != token_folder:
                return _response_json(403, {"error": "folder_not_allowed"})

            prefix = BASE_PREFIX + req_folder

            files, zip_key = _list_folder_for_prefix(prefix)

            if method == "HEAD":
                return {
                    "statusCode": 200,
                    "headers": {
                        "Cache-Control": f"public, max-age={LIST_CACHE_TTL_SECONDS}, s-maxage={LIST_CACHE_TTL_SECONDS}"
                    },
                    "body": ""
                }

            out = {"folder": prefix, "files": files}
            if zip_key:
                out["zip"] = zip_key

            return _response_json(
                200,
                out,
                cache_control=f"public, max-age={LIST_CACHE_TTL_SECONDS}, s-maxage={LIST_CACHE_TTL_SECONDS}"
            )

        return _response_json(404, {"error": "not_found"})

    except ValueError as ve:
        if wants_redirect:
            return _redirect_error(400, "bad_request")
        return _response_json(400, {"error": str(ve)})

    except Exception as e:
        print("UNHANDLED_EXCEPTION:", repr(e))
        if wants_redirect:
            return _redirect_error(500, "internal_error")
        return _response_json(500, {"error": "internal_error", "detail": str(e)})