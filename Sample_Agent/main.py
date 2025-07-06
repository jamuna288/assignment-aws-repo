import sys
import os
from fastapi import FastAPI
from pydantic import BaseModel
from agent.agentf import run_agent
from fastapi.middleware.cors import CORSMiddleware
import datetime

sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), '..')))

app = FastAPI(
    title="Flight Agent API",
    description="Intelligent flight assistance agent with automated CI/CD deployment",
    version="2.0"
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # Allow all origins
    allow_credentials=True,
    allow_methods=["*"],  # Allow all HTTP methods
    allow_headers=["*"],  # Allow all headers
)

class Query(BaseModel):
    input_text: str

@app.get("/")
async def root():
    return {
        "message": "Flight Agent API is running", 
        "version": "2.0",
        "deployment_time": datetime.datetime.now().isoformat(),
        "status": "active"
    }

@app.get("/version")
async def get_version():
    return {
        "version": "2.0",
        "deployment_time": datetime.datetime.now().isoformat(),
        "auto_deployment": "enabled",
        "last_update": "Agent code modified for auto-deployment test"
    }

@app.post("/recommendation")
def recommend(query: Query):
    result = run_agent(query.input_text)
    return {"response": result}
