# list_blobs_chunk_activity.py

import os
from functools import lru_cache
from typing import Dict, List

from azure.identity import DefaultAzureCredential
from azure.storage.blob import BlobServiceClient

from application.app import app

credential = DefaultAzureCredential()


@lru_cache(maxsize=4)
def _get_blob_service_client(account_name: str) -> BlobServiceClient:
    if not account_name:
        raise ValueError("SOURCE_STORAGE_ACCOUNT_NAME is not set")
    return BlobServiceClient(
        account_url=f"https://{account_name}.blob.core.windows.net/",
        credential=credential,
    )

@app.function_name(name="list_blobs_chunk")
@app.activity_trigger(input_name="params")
def list_blobs_chunk(params: dict):
    container_name = params.get("container_name")
    continuation_token = params.get("continuation_token")
    prefix_list_offset = params.get("prefix_list_offset", 0)
    chunk_size = params.get("chunk_size", 1000)
    prefix_list = params.get("prefix_list")
    if not container_name:
        raise ValueError("container_name is required")
    if not prefix_list:
        prefix_list = [""]
    
    if len(prefix_list) <= prefix_list_offset:
        return {
            "blobs": [],
            "continuation_token": None,
            "prefix_list_offset": prefix_list_offset
        }

    # Use connection string from Application Settings (local.settings.json for local dev)
    source_account_name = os.getenv("SOURCE_STORAGE_ACCOUNT_NAME")
    source_blob_service_client = _get_blob_service_client(source_account_name)
    container_client = source_blob_service_client.get_container_client(container_name)

    # List blobs in a segment (page) using a continuation token
    blob_identifiers: List[Dict[str, str]] = []
    result_segment = container_client.list_blobs(
        name_starts_with=prefix_list[prefix_list_offset],
        results_per_page=chunk_size
    )

    new_continuation_token = None
    pages = result_segment.by_page(continuation_token=continuation_token)
    for page in pages:
        for blob in page:
            blob_identifiers.append(
                {
                    "account_name": source_account_name,
                    "container_name": container_name,
                    "blob_name": blob.name,
                }
            )
        new_continuation_token = pages.continuation_token
        if not new_continuation_token:
            prefix_list_offset += 1
        break

    return {
        "blobs": blob_identifiers,
        "continuation_token": new_continuation_token,
        "prefix_list_offset": prefix_list_offset
    }
