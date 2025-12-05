from azure.durable_functions import DurableOrchestrationContext, RetryOptions
from activities.search import ensure_index_exists,add_documents
from activities.listblob import list_blobs_chunk
from activities.cracking import document_cracking
from activities.chunking import chunking
from activities.embedding import embedding

from application.app import app
import os
import logging



@app.function_name(name="index")  # The name used by client.start_new("index")
@app.orchestration_trigger(context_name="context")
def index(context: DurableOrchestrationContext):
    # Resolver resolves list of prefixes to iterable ( needs to store state of iterable e.g. marker and array position)
    logging.info("Starting orchestration 'index'")
    input = context.get_input()
    continuation_token = None
    array_position = 0
    container_name = input.get("defaults").get("BLOB_CONTAINER_NAME")
    if container_name is None:
        raise ValueError("BLOB_CONTAINER_NAME is not set")
    index_name = input.get("index_name") or input.get("defaults").get("SEARCH_INDEX_NAME")
    if index_name is None:
        raise ValueError("SEARCH_INDEX_NAME is not set")
    blob_amount_parallel = input.get("defaults").get("BLOB_AMOUNT_PARALLEL")
    if blob_amount_parallel is None:
        raise ValueError("BLOB_AMOUNT_PARALLEL is not set")
    max_number_of_attempts = input.get("defaults").get("MAX_NUMBER_OF_ATTEMPTS")
    if max_number_of_attempts is None:
        raise ValueError("MAX_NUMBER_OF_ATTEMPTS is not set")
    
    
    yield context.call_activity(name="ensure_index_exists", input_=index_name)
    # For every item in iterable create a sub orchestrator ( should be every file in the blob storage)
    while True:
        prefix_list = [""] if "prefix_list" not in input else input["prefix_list"] 
        blob_list_result = yield context.call_activity("list_blobs_chunk", {
                    "container_name": container_name,
                    "continuation_token": continuation_token,
                    "chunk_size": blob_amount_parallel,
                    "prefix_list_offset": array_position,
                    "prefix_list": prefix_list
            })
        if len(blob_list_result["blobs"]) == 0:
            break
        continuation_token = blob_list_result["continuation_token"]
        array_position = blob_list_result["prefix_list_offset"]
        task_list = []
        for blob_reference in blob_list_result["blobs"]:
            document_retry_options = RetryOptions(first_retry_interval_in_milliseconds=60_000, max_number_of_attempts=max_number_of_attempts)
            task_list.append(context.call_sub_orchestrator_with_retry(
                name="index_document",
                retry_options=document_retry_options,
                input_={"blob_reference": blob_reference, "index_name": index_name, "max_number_of_attempts": max_number_of_attempts}))
        yield context.task_all(task_list)
    

@app.function_name(name="index_document")  # The name used by client.start_new("index")
@app.orchestration_trigger(context_name="context")
def index_document(context: DurableOrchestrationContext):
    input = context.get_input()
    service_retry_options = RetryOptions(first_retry_interval_in_milliseconds=3000, max_number_of_attempts=input["max_number_of_attempts"])
    document = yield context.call_activity_with_retry("document_cracking", service_retry_options, input["blob_reference"])
    chunks = yield context.call_activity("chunking", document)
    chunks_with_embeddings = yield context.call_activity_with_retry("embedding", service_retry_options, chunks)
    yield context.call_activity_with_retry("add_documents",  service_retry_options,{"chunks": chunks_with_embeddings, "index_name": input["index_name"]})