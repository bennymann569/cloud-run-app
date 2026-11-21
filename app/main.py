import os
from fastapi import FastAPI

app = FastAPI(title="Cloud Run App", version="1.0.0")
ENVIRONMENT = os.getenv("APP_ENVIRONMENT", "local")
VERSION = os.getenv("APP_VERSION", "dev")


@app.get("/healthz")
def healthz():
    return {"status": "ok", "environment": ENVIRONMENT}


@app.get("/")
def root():
    return {"service": "cloud-run-app", "environment": ENVIRONMENT, "version": VERSION}
