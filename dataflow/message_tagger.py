import apache_beam as beam
import json


class TagElementWithDestinationTable(beam.DoFn):
    ATTR_KEY = "destination_table"

    def __init__(self, tables):
        self.tables = tables

    def process(self, element):
        if TagElementWithDestinationTable.ATTR_KEY in element.attributes and element.attributes[TagElementWithDestinationTable.ATTR_KEY] in self.tables:
            yield beam.pvalue.TaggedOutput(element.attributes[TagElementWithDestinationTable.ATTR_KEY], json.loads(element.data))
        else:
            yield beam.pvalue.TaggedOutput("dlq", element)