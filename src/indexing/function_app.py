import os
import sys
import logging
import azure.functions as func
import azure.durable_functions as df
from azure.durable_functions import DurableOrchestrationClient


from application.app import app
from orchestrators.index import index

defaults = {
    "BLOB_AMOUNT_PARALLEL": int(os.environ.get("BLOB_AMOUNT_PARALLEL", "20")),
    "SEARCH_INDEX_NAME": os.environ.get("SEARCH_INDEX_NAME", "default-index"),
    "BLOB_CONTAINER_NAME": os.environ.get("BLOB_CONTAINER_NAME", "source"),
    "MAX_NUMBER_OF_ATTEMPTS": int(os.environ.get("MAX_NUMBER_OF_ATTEMPTS", "1")),
}


def extract_path(event: func.EventGridEvent):
    subject = event.subject
    path_in_container = subject.split("/blobs/", 1)[-1]
    return path_in_container


# @app.function_name(name='index_event_grid')
# @app.event_grid_trigger(arg_name='event')
# async def index_event_grid(event: func.EventGridEvent):
#     if event.get_json()["api"] != "PutBlob":
#         logging.info("Event type is not BlobCreated. Skipping execution.")
#         return
    
#     path_in_container = extract_path(event)
#     logging.info(f'Python EventGrid trigger processed a BlobCreated event. Path: {path_in_container}')

    # instance_id = await client.start_new("index", client_input={"prefix_list": [path_in_container], "defaults": defaults})
    # logging.info(f'Started indexing with id: {instance_id}')

#
#app = func.FunctionApp(http_auth_level=func.AuthLevel.ANONYMOUS)
#app = df.DFApp(http_auth_level=func.AuthLevel.ANONYMOUS)

@app.function_name(name='index_http')
@app.route(route="index", methods=[func.HttpMethod.POST])
@app.durable_client_input(client_name="client")
async def index_http(req: func.HttpRequest, client: DurableOrchestrationClient) -> func.HttpResponse:
    logging.info('Kick off indexing process.')
    input = req.get_json()
    instance_id = await client.start_new(
        orchestration_function_name="index",
        client_input={"prefix_list": input['prefix_list'], "index_name": input['index_name'], "defaults": defaults})
    return func.HttpResponse(instance_id, status_code=200)

#anonymous 
# @app.route(route="http_trigger")

# def http_trigger(req: func.HttpRequest) -> func.HttpResponse:
#     logging.info('Python HTTP trigger function processed a request.')

#     name = req.params.get('name')
#     if not name:
#         try:
#             req_body = req.get_json()
#         except ValueError:
#             pass
#         else:
#             name = req_body.get('name')

#     if name:
#         return func.HttpResponse(f"Hello, {name}. This HTTP triggered function executed successfully.")
#     else:
#         return func.HttpResponse(
#              "This HTTP triggered function executed successfully. Pass a name in the query string or in the request body for a personalized response.",
#              status_code=200
#         )