import apache_beam as beam
# import argparse

from apache_beam import io as beam_io
from apache_beam.io.gcp.internal.clients import bigquery
from apache_beam.options.pipeline_options import PipelineOptions
from dataflow.message_tagger import TagElementWithDestinationTable
from dataflow.metastore_service import MetastoreService

class IngestionOptions(PipelineOptions):
    @classmethod
    def _add_argparse_args(cls, parser):
        parser.add_argument(
            '--gcp_project_id',
            required=True,
            help='GCP ProjectId hosting Dataflow, Pubsub and BigQuery')
        parser.add_argument(
            '--subscription_id',
            required=True,
            help='PubSub SubscriptionId to pull events from')
        parser.add_argument(
            '--dataset_id',
            required=True,
            help='GCP BigQuery Dataset storing tables in scope to store events')


pipeline_options = PipelineOptions()
ingestion_options = pipeline_options.view_as(IngestionOptions)

metastore_service = MetastoreService()
tables = metastore_service.get_tables(f"{ingestion_options.gcp_project_id}.{ingestion_options.dataset_id}")

with beam.Pipeline(options=pipeline_options) as p:
    messages = (
        p
        | "Read from Pub/Sub"
        >> beam_io.ReadFromPubSub(
            subscription=ingestion_options.subscription_id, with_attributes=True
        )
        | "Tag message with destination table"
        >> beam.ParDo(TagElementWithDestinationTable(tables)).with_outputs(*tables, "dlq")
    )

    for destination_table in tables:
        messages[destination_table] | f"Write to BigQuery {destination_table}" >> beam.io.WriteToBigQuery(
            table=bigquery.TableReference(
                projectId=ingestion_options.gcp_project_id,
                datasetId=ingestion_options.dataset_id,
                tableId=destination_table,
            ),
            schema=metastore_service.get_table_schema(
                f"{ingestion_options.gcp_project_id}.{ingestion_options.dataset_id}.{destination_table}"
            ),
            write_disposition=beam.io.BigQueryDisposition.WRITE_APPEND,
            create_disposition=beam.io.BigQueryDisposition.CREATE_IF_NEEDED,
            method="STREAMING_INSERTS",
        )

    messages["dlq"] | f"Write messages with unknown destinations to DLQ" >> beam.io.WriteToPubSub(topic=f"projects/{ingestion_options.gcp_project_id}/topics/dlq", with_attributes=True)
