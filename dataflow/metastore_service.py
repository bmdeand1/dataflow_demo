import io
import json

from google.cloud import bigquery


class MetastoreService:
    def __init__(self):
        self.bq_client = bigquery.Client()

    def get_tables(self, dataset_id):
        return [t.table_id for t in self.bq_client.list_tables(dataset_id)]

    def get_table_schema(self, table_id):
        table = self.bq_client.get_table(table_id)
        f = io.StringIO("")
        self.bq_client.schema_to_json(table.schema, f)
        return {"fields": json.loads(f.getvalue())}
