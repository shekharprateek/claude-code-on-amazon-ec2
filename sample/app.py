"""
FastAPI application entry point.
"""

from fastapi import FastAPI

from .api.routes import router

app = FastAPI(title="Sample App", version="1.0.0")
app.include_router(router)


@app.get("/")
def root():
    """Root endpoint."""
    return {"message": "Sample app is running"}
