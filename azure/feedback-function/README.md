# PlaceLore Feedback Function

Ingestion endpoint for place-prediction feedback from the iOS app.

## Endpoint

`POST /api/feedback`

The function validates the JSON payload sent by `PredictionFeedbackUploader`. The request body may be a single feedback object or an array of feedback objects. It writes one JSON document per feedback event to ADLS Gen2:

`feedback/prediction-feedback/<debug|release>/YYYY/MM/DD/<eventID>.json`

## App Settings

- `FEEDBACK_STORAGE_ACCOUNT`: ADLS Gen2 storage account name.
- `FEEDBACK_FILE_SYSTEM`: ADLS Gen2 filesystem/container name.
- `FEEDBACK_DIRECTORY`: root directory for uploaded feedback.
- `FEEDBACK_API_KEY`: optional shared key. When set, requests must include the same value in `x-placelore-feedback-key`.

## Identity

The deployed Function App should use a managed identity with `Storage Blob Data Contributor` on the target storage account.

## Deploy

From this directory:

```sh
zip -r /tmp/placelore-feedback-function.zip . \
  -x 'local.settings.json' 'local.settings.sample.json' '.venv/*' '__pycache__/*' '*.pyc'

az functionapp config appsettings set \
  -g rg-placelore-feedback-dev \
  -n func-placelore-feedback-dev \
  --settings \
    FEEDBACK_STORAGE_ACCOUNT=stplacelorefbdev909 \
    FEEDBACK_FILE_SYSTEM=feedback \
    FEEDBACK_DIRECTORY=prediction-feedback

az functionapp deployment source config-zip \
  -g rg-placelore-feedback-dev \
  -n func-placelore-feedback-dev \
  --src /tmp/placelore-feedback-function.zip \
  --build-remote true
```
