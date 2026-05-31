import json
import logging
import os
from datetime import datetime, timezone
from typing import Any

import azure.functions as func
from azure.identity import DefaultAzureCredential
from azure.core.exceptions import ResourceExistsError
from azure.storage.filedatalake import DataLakeServiceClient

app = func.FunctionApp(http_auth_level=func.AuthLevel.ANONYMOUS)

REQUIRED_FIELDS = {
    "schemaVersion": int,
    "appVersion": str,
    "appBuild": str,
    "buildConfiguration": str,
    "eventID": str,
    "createdAt": str,
    "visitID": str,
    "arrivalDate": str,
    "latitude": (int, float),
    "longitude": (int, float),
    "predictedPlaceName": str,
    "confidence": str,
    "alternativeCount": int,
    "verdict": str,
    "wasAccurate": bool,
}


def _json_response(status_code: int, body: dict[str, Any]) -> func.HttpResponse:
    return func.HttpResponse(
        json.dumps(body, separators=(",", ":")),
        status_code=status_code,
        mimetype="application/json",
    )


def _validate_api_key(req: func.HttpRequest) -> bool:
    expected_key = os.getenv("FEEDBACK_API_KEY", "")
    if not expected_key:
        return True
    return req.headers.get("x-placelore-feedback-key") == expected_key


def _parse_iso8601(value: str) -> datetime:
    normalized = value.replace("Z", "+00:00")
    return datetime.fromisoformat(normalized).astimezone(timezone.utc)


def _validate_payload(payload: dict[str, Any]) -> list[str]:
    errors: list[str] = []
    for field, expected_type in REQUIRED_FIELDS.items():
        if field not in payload:
            errors.append(f"Missing {field}")
        elif not isinstance(payload[field], expected_type):
            errors.append(f"Invalid {field}")

    if payload.get("schemaVersion") != 1:
        errors.append("Unsupported schemaVersion")
    if payload.get("buildConfiguration") != "debug":
        errors.append("Only debug feedback is accepted")

    for date_field in ("createdAt", "arrivalDate"):
        if isinstance(payload.get(date_field), str):
            try:
                _parse_iso8601(payload[date_field])
            except ValueError:
                errors.append(f"Invalid {date_field}")

    return errors


def _feedback_path(payload: dict[str, Any]) -> str:
    created_at = _parse_iso8601(payload["createdAt"])
    directory = os.getenv("FEEDBACK_DIRECTORY", "prediction-feedback/debug").strip("/")
    return (
        f"{directory}/"
        f"{created_at:%Y/%m/%d}/"
        f"{payload['eventID']}.json"
    )


def _service_client() -> DataLakeServiceClient:
    account_name = os.environ["FEEDBACK_STORAGE_ACCOUNT"]
    account_url = f"https://{account_name}.dfs.core.windows.net"
    return DataLakeServiceClient(
        account_url=account_url,
        credential=DefaultAzureCredential(),
    )


def _write_feedback(payload: dict[str, Any]) -> str:
    file_system_name = os.getenv("FEEDBACK_FILE_SYSTEM", "feedback")
    destination_path = _feedback_path(payload)
    parent_directory = destination_path.rsplit("/", maxsplit=1)[0]
    envelope = {
        "ingestedAt": datetime.now(timezone.utc).isoformat(),
        "source": "placelore-ios-debug",
        "payload": payload,
    }
    data = json.dumps(envelope, separators=(",", ":"), sort_keys=True).encode("utf-8")

    file_system = _service_client().get_file_system_client(file_system_name)
    _ensure_directory(file_system, parent_directory)
    file_client = file_system.get_file_client(destination_path)
    file_client.upload_data(data, overwrite=True)
    return destination_path


def _ensure_directory(file_system: Any, directory_path: str) -> None:
    current_path = ""
    for segment in directory_path.split("/"):
        current_path = f"{current_path}/{segment}" if current_path else segment
        try:
            file_system.create_directory(current_path)
        except ResourceExistsError:
            continue


@app.route(route="feedback", methods=["POST"])
def feedback(req: func.HttpRequest) -> func.HttpResponse:
    if not _validate_api_key(req):
        return _json_response(401, {"error": "Unauthorized"})

    try:
        payload = req.get_json()
    except ValueError:
        return _json_response(400, {"error": "Invalid JSON"})

    if not isinstance(payload, dict):
        return _json_response(400, {"error": "JSON body must be an object"})

    errors = _validate_payload(payload)
    if errors:
        return _json_response(400, {"error": "Invalid payload", "details": errors})

    try:
        path = _write_feedback(payload)
    except Exception:
        logging.exception("Failed to write feedback payload")
        return _json_response(500, {"error": "Failed to store feedback"})

    return _json_response(202, {"status": "accepted", "path": path})
