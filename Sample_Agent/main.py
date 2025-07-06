import sys
import os
from fastapi import FastAPI
from pydantic import BaseModel
from agent.agentf import run_agent
from fastapi.middleware.cors import CORSMiddleware

sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), '..')))

app = FastAPI()

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # Allow all origins
    allow_credentials=True,
    allow_methods=["*"],  # Allow all HTTP methods
    allow_headers=["*"],  # Allow all headers
)

class Query(BaseModel):
    input_text: str

@app.post("/recommendation")
def recommend(query: Query):
    result = run_agent(query.input_text)
    return {"response": result}
