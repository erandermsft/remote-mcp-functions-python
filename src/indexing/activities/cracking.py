import os
from functools import lru_cache
from typing import Dict
from urllib.parse import unquote

from azure.ai.documentintelligence import DocumentIntelligenceClient
from azure.ai.documentintelligence.models import AnalyzeDocumentRequest, AnalyzeResult
from azure.identity import DefaultAzureCredential
from azure.storage.blob import BlobServiceClient

from application.app import app

credential = DefaultAzureCredential()


@lru_cache(maxsize=1)
def _get_document_client(endpoint: str) -> DocumentIntelligenceClient:
    if not endpoint:
        raise ValueError("DI_ENDPOINT is not set")
    return DocumentIntelligenceClient(endpoint, credential)


@lru_cache(maxsize=4)
def _get_blob_service_client(account_name: str) -> BlobServiceClient:
    if not account_name:
        raise ValueError("Blob reference missing account_name")
    return BlobServiceClient(
        account_url=f"https://{account_name}.blob.core.windows.net/",
        credential=credential,
    )

@app.function_name(name="document_cracking")
@app.activity_trigger(input_name="blob_reference")
def document_cracking(blob_reference: Dict[str, str]):
    endpoint = os.getenv('DI_ENDPOINT')
    client = _get_document_client(endpoint)

    blob_client = _get_blob_service_client(blob_reference.get("account_name")).get_blob_client(
        blob_reference.get("container_name"),
        blob_reference.get("blob_name"),
    )
    document_bytes = blob_client.download_blob().readall()

    poller = client.begin_analyze_document(
        "prebuilt-layout",
        AnalyzeDocumentRequest(bytes_source=document_bytes)
    )
    result: AnalyzeResult = poller.result()

    return {
        "pages": ["".join([line['content'] for line in page.lines]) for page in result.pages],
        "url": blob_client.url,
        "filename": unquote(blob_reference.get("blob_name", "").split("/")[-1]),
        "blob_reference": blob_reference,
    }