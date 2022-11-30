provider "google" {
  project = var.gcp_project_id
  region  = var.region
}

locals {
  tables = {
    example_table_one = {
      schema = "./schemas/example_table_one.json"
    }
    example_table_two = {
      schema = "./schemas/example_table_two.json"
    }
    # example_table_three = {
    #   schema = "./schemas/example_table_one.json"
    # }
  }
}

resource "google_compute_network" "vpc-network" {
  name = "vpc-network"
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "subnetwork-df-workers" {
  name          = "df-workers"
  ip_cidr_range = "10.0.1.0/24"
  region        = "europe-west2"
  network       = google_compute_network.vpc-network.id
  private_ip_google_access = true
}

resource "google_compute_firewall" "allow-12345-12346" {
  name    = "allow-12345-12346"
  source_ranges = ["10.0.1.0/24"]
  network = google_compute_network.vpc-network.name

  allow {
    protocol = "tcp"
    ports    = ["12345-12346"]
  }
}

resource "google_storage_bucket" "df_demo_templates" {
  name          = "df-demo-templates-${var.gcp_project_id}"
  location      = var.region
  force_destroy = true
  uniform_bucket_level_access = true

  public_access_prevention = "enforced"
}

resource "google_pubsub_topic" "example_topic" {
  name = "example_topic"
}

resource "google_pubsub_subscription" "example_subscription" {
  name  = "example_subscription"
  topic = google_pubsub_topic.example_topic.name
}

resource "google_pubsub_topic" "dlq" {
  name = "dlq"
}

resource "google_bigquery_dataset" "example_dataset" {
  dataset_id = "example_dataset"
  location   = "EU"
}

resource "google_bigquery_table" "table" {
  for_each   = local.tables
  dataset_id = google_bigquery_dataset.example_dataset.dataset_id
  table_id   = each.key
  schema     = file("${each.value.schema}")
  deletion_protection = false
}

resource "google_service_account" "dataflow_service_account" {
  account_id   = "dataflow-service-account"
  display_name = "Dataflow Service Account"
}

resource "google_project_iam_member" "storage_admin_binding" {
  project = var.gcp_project_id
  role = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.dataflow_service_account.email}"
}

resource "google_project_iam_member" "dataflow_service_agent_binding" {
  project = var.gcp_project_id
  role = "roles/dataflow.serviceAgent"
  member = "serviceAccount:${google_service_account.dataflow_service_account.email}"
}

resource "google_project_iam_member" "dataflow_worker_binding" {
  project = var.gcp_project_id
  role = "roles/dataflow.worker"
  member = "serviceAccount:${google_service_account.dataflow_service_account.email}"
}

resource "google_project_iam_member" "pubsub_admin_binding" {
  project = var.gcp_project_id
  role = "roles/pubsub.admin"
  member = "serviceAccount:${google_service_account.dataflow_service_account.email}"
}

resource "google_project_iam_member" "bigquery_admin_binding" {
  project = var.gcp_project_id
  role = "roles/bigquery.admin"
  member = "serviceAccount:${google_service_account.dataflow_service_account.email}"
}

resource "null_resource" "df_trigger" {
  triggers = {
    tables = join(",", keys(local.tables))
  }

  provisioner "local-exec" {
    working_dir = "${path.module}/../"
    command = "GCP_PROJECT_ID=${var.gcp_project_id} GCP_REGION=${var.region} GCS_DATAFLOW_BUCKET=${google_storage_bucket.df_demo_templates.name} ./scripts/deploy_dataflow_template"
  }

  depends_on = [
    google_storage_bucket.df_demo_templates
  ]
}

resource "google_dataflow_job" "dataflow_demo" {
  name              = "dataflow_demo"
  service_account_email = google_service_account.dataflow_service_account.email
  ip_configuration = "WORKER_IP_PRIVATE"
  template_gcs_path = "gs://${google_storage_bucket.df_demo_templates.name}/templates/dataflow-demo"
  temp_gcs_location = "gs://${google_storage_bucket.df_demo_templates.name}/temp/"
  subnetwork = "regions/${google_compute_subnetwork.subnetwork-df-workers.region}/subnetworks/${google_compute_subnetwork.subnetwork-df-workers.name}"

  parameters = {
    "gcp_project_id" = var.gcp_project_id
    "subscription_id" = google_pubsub_subscription.example_subscription.id
    "dataset_id" = google_bigquery_dataset.example_dataset.dataset_id
  }

  depends_on = [
    google_bigquery_table.table, null_resource.df_trigger
  ]

  lifecycle {
    replace_triggered_by = [null_resource.df_trigger]
  }
}