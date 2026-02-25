import os
import posixpath
import uuid
from urllib.parse import unquote_plus

import boto3
from botocore.exceptions import ClientError
from PIL import Image, ImageOps, ImageDraw, ImageFont

s3 = boto3.client("s3")

# --- Source / destination layout ---
SOURCE_PREFIX = os.getenv("SOURCE_PREFIX", "gallery/").strip().lstrip("/")
if SOURCE_PREFIX and not SOURCE_PREFIX.endswith("/"):
    SOURCE_PREFIX += "/"

# NEW: thumbs go under a different top-level prefix
THUMB_ROOT_PREFIX = os.getenv("THUMB_ROOT_PREFIX", "thumbs/").strip().strip("/") + "/"

# thumb filename prefix
THUMB_PREFIX = os.getenv("THUMB_PREFIX", "thumb-of-")

# --- Thumb output ---
THUMB_MAX_SIZE = int(os.getenv("THUMB_MAX_SIZE", "640"))
JPEG_QUALITY   = int(os.getenv("JPEG_QUALITY", "75"))
CACHE_CONTROL  = os.getenv("CACHE_CONTROL", "public, max-age=31536000, immutable")

# --- Decider ---
THUMB_DECIDER_MODE = os.getenv("THUMB_DECIDER_MODE", "bytes").strip().lower()  # bytes|pixels
THUMB_DECIDER_MIN_MIB = float(os.getenv("THUMB_DECIDER_MIN_MIB", "0"))
THUMB_DECIDER_MIN_MAXDIM_PX = int(os.getenv("THUMB_DECIDER_MIN_MAXDIM_PX", "0"))

# Optional: create folder marker so S3 browsers show thumbs/<album>/
CREATE_THUMB_FOLDER_MARKER = os.getenv("CREATE_THUMB_FOLDER_MARKER", "true").lower() == "true"

# Extensions
IMAGE_EXTS = {".jpg", ".jpeg", ".png", ".webp", ".tif", ".tiff", ".bmp", ".gif"}
VIDEO_EXTS = {".mp4", ".mov", ".webm", ".m4v", ".avi"}  # adjust as needed


def _ext(key: str) -> str:
    return (posixpath.splitext(key)[1] or "").lower()


def is_image_key(key: str) -> bool:
    return _ext(key) in IMAGE_EXTS


def is_video_key(key: str) -> bool:
    return _ext(key) in VIDEO_EXTS


def is_thumb_key(key: str) -> bool:
    # thumbs are outside gallery/, but keep a guard anyway
    return key.startswith(THUMB_ROOT_PREFIX)


def _rel_from_source(key: str) -> str:
    # gallery/<album>/file -> <album>/file
    rel = key[len(SOURCE_PREFIX):] if key.startswith(SOURCE_PREFIX) else key
    return rel.lstrip("/")


def thumb_key_for(original_key: str, out_ext: str) -> str:
    # thumbs/<album>/thumb-of-<file>.<out_ext>
    rel = _rel_from_source(original_key)
    rel_dir = posixpath.dirname(rel)   # <album>
    base = posixpath.basename(rel)     # file.ext

    if rel_dir and rel_dir != ".":
        dest_dir = posixpath.join(THUMB_ROOT_PREFIX.rstrip("/"), rel_dir)
    else:
        dest_dir = THUMB_ROOT_PREFIX.rstrip("/")

    thumb_key = posixpath.join(dest_dir, f"{THUMB_PREFIX}{base}")
    root, _ = posixpath.splitext(thumb_key)
    return root + out_ext


def ensure_thumb_folder_marker(bucket: str, original_key: str):
    # Create thumbs/<album>/ as a visible "folder" for S3 GUI tools
    rel = _rel_from_source(original_key)
    rel_dir = posixpath.dirname(rel)

    if rel_dir and rel_dir != ".":
        marker_key = posixpath.join(THUMB_ROOT_PREFIX.rstrip("/"), rel_dir) + "/"
    else:
        marker_key = THUMB_ROOT_PREFIX

    try:
        s3.head_object(Bucket=bucket, Key=marker_key)
        return
    except ClientError as e:
        code = e.response.get("Error", {}).get("Code", "")
        if code not in ("404", "NoSuchKey", "NotFound"):
            raise

    s3.put_object(
        Bucket=bucket,
        Key=marker_key,
        Body=b"",
        ContentType="application/x-directory",
        CacheControl="no-store",
    )


def choose_output_for_image(img: Image.Image):
    # If transparency -> PNG, else JPEG
    mode = (img.mode or "").upper()
    has_alpha = ("A" in mode) or ("transparency" in img.info)
    if has_alpha:
        return ("PNG", "image/png", ".png")
    return ("JPEG", "image/jpeg", ".jpg")


def bytes_threshold() -> int:
    if THUMB_DECIDER_MIN_MIB <= 0:
        return 0
    return int(THUMB_DECIDER_MIN_MIB * 1024 * 1024)


def should_process_by_bytes(obj_size: int) -> bool:
    thr = bytes_threshold()
    return True if thr <= 0 else (obj_size >= thr)


def should_process_by_pixels(max_dim: int) -> bool:
    thr = THUMB_DECIDER_MIN_MAXDIM_PX
    return True if thr <= 0 else (max_dim >= thr)


def render_video_placeholder(out_path: str, size: int, label: str = "VIDEO"):
    # Simple JPEG placeholder using Pillow only (no ffmpeg)
    w = max(240, int(size))
    h = max(135, int(w * 9 / 16))  # 16:9
    im = Image.new("RGB", (w, h), (12, 12, 12))
    draw = ImageDraw.Draw(im)

    cx, cy = w // 2, h // 2
    tri = [(cx - w//12, cy - h//10), (cx - w//12, cy + h//10), (cx + w//10, cy)]
    draw.polygon(tri, fill=(240, 240, 240))

    try:
        font = ImageFont.load_default()
    except Exception:
        font = None
    txt = label
    bbox = draw.textbbox((0, 0), txt, font=font)
    tw, th = (bbox[2] - bbox[0], bbox[3] - bbox[1])
    draw.text((10, h - th - 10), txt, fill=(200, 200, 200), font=font)

    im.save(out_path, format="JPEG", quality=JPEG_QUALITY, optimize=True, progressive=True)


def lambda_handler(event, context):
    records = event.get("Records", [])
    out = {"processed": 0, "skipped": 0, "errors": 0, "items": []}

    mode = THUMB_DECIDER_MODE if THUMB_DECIDER_MODE in ("bytes", "pixels") else "bytes"

    for r in records:
        try:
            bucket = r["s3"]["bucket"]["name"]
            key = unquote_plus(r["s3"]["object"]["key"])

            # Only react to objects under gallery/
            if not key.startswith(SOURCE_PREFIX) or key.endswith("/") or is_thumb_key(key):
                out["skipped"] += 1
                out["items"].append({"key": key, "status": "skipped", "reason": "not_source"})
                continue

            is_img = is_image_key(key)
            is_vid = is_video_key(key)
            if not (is_img or is_vid):
                out["skipped"] += 1
                out["items"].append({"key": key, "status": "skipped", "reason": "not_image_or_video"})
                continue

            obj_size = int(r["s3"]["object"].get("size", 0) or 0)

            # Bytes mode: skip before download
            if mode == "bytes" and not should_process_by_bytes(obj_size):
                out["skipped"] += 1
                out["items"].append({"key": key, "status": "skipped", "reason": "bytes_gate", "obj_size": obj_size})
                continue

            if CREATE_THUMB_FOLDER_MARKER:
                ensure_thumb_folder_marker(bucket, key)

            out_tmp = f"/tmp/out-{uuid.uuid4().hex}"

            # Videos: create a placeholder thumbnail (JPEG) without downloading video
            if is_vid:
                content_type = "image/jpeg"
                out_ext = ".jpg"
                thumb_key = thumb_key_for(key, out_ext)

                render_video_placeholder(out_tmp, THUMB_MAX_SIZE, label="VIDEO")

                s3.upload_file(
                    out_tmp,
                    bucket,
                    thumb_key,
                    ExtraArgs={"ContentType": content_type, "CacheControl": CACHE_CONTROL},
                )

                out["processed"] += 1
                out["items"].append({"key": key, "thumb": thumb_key, "status": "ok", "type": "video", "obj_size": obj_size})
                continue

            # Images: download and resize
            src_tmp = f"/tmp/src-{uuid.uuid4().hex}"
            s3.download_file(bucket, key, src_tmp)

            with Image.open(src_tmp) as im:
                im = ImageOps.exif_transpose(im)
                w, h = im.size
                max_dim = max(w, h)

                # Pixels mode: gate after open
                if mode == "pixels" and not should_process_by_pixels(max_dim):
                    out["skipped"] += 1
                    out["items"].append({"key": key, "status": "skipped", "reason": "pixels_gate", "dims": [w, h]})
                    continue

                im.thumbnail((THUMB_MAX_SIZE, THUMB_MAX_SIZE), Image.Resampling.LANCZOS)

                fmt, content_type, out_ext = choose_output_for_image(im)
                thumb_key = thumb_key_for(key, out_ext)

                save_kwargs = {}
                if fmt == "JPEG":
                    if im.mode not in ("RGB", "L"):
                        im = im.convert("RGB")
                    save_kwargs = {"quality": JPEG_QUALITY, "optimize": True, "progressive": True}
                else:
                    save_kwargs = {"optimize": True}

                im.save(out_tmp, format=fmt, **save_kwargs)

            s3.upload_file(
                out_tmp,
                bucket,
                thumb_key,
                ExtraArgs={"ContentType": content_type, "CacheControl": CACHE_CONTROL},
            )

            out["processed"] += 1
            out["items"].append({"key": key, "thumb": thumb_key, "status": "ok", "type": "image", "obj_size": obj_size})

        except Exception as e:
            out["errors"] += 1
            out["items"].append({"key": r.get("s3", {}).get("object", {}).get("key"), "status": "error", "error": str(e)})

    return out