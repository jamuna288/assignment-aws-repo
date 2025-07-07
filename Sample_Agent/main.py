import sys
import os
import logging
from fastapi import FastAPI
from pydantic import BaseModel
from agent.agentf import run_agent
from fastapi.middleware.cors import CORSMiddleware
import datetime

sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), '..')))

# Configure logging to save to logs/agent.log as requested
log_dir = "/opt/agent/logs"
os.makedirs(log_dir, exist_ok=True)

# Set up logging configuration
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler(f'{log_dir}/agent.log', mode='a'),
        logging.StreamHandler(sys.stdout)
    ]
)

logger = logging.getLogger(__name__)

app = FastAPI(
    title="Flight Agent API",
    description="Intelligent flight assistance agent with automated CI/CD deployment and comprehensive logging - Workflow Test v2.1",
    version="2.1"
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

@app.on_event("startup")
async def startup_event():
    """Log application startup"""
    logger.info("🚀 Flight Agent API starting up...")
    logger.info(f"📝 Logging configured to save to: {log_dir}/agent.log")
    logger.info(f"🕐 Startup time: {datetime.datetime.now().isoformat()}")
    logger.info("🔄 Workflow rerun test - fixing AWS region issue")
    logger.info("🔐 All GitHub secrets configured - testing full deployment")

@app.on_event("shutdown")
async def shutdown_event():
    """Log application shutdown"""
    logger.info("🛑 Flight Agent API shutting down...")
    logger.info(f"🕐 Shutdown time: {datetime.datetime.now().isoformat()}")

@app.get("/")
async def root():
    logger.info("📍 Root endpoint accessed")
    return {
        "message": "🚀 Flight Agent API is running smoothly - CI/CD Test v2.1", 
        "version": "2.1",
        "deployment_time": datetime.datetime.now().isoformat(),
        "status": "active",
        "test_deployment": "✅ Workflow test successful!",
        "logging": {
            "enabled": True,
            "location": f"{log_dir}/agent.log"
        }
    }

@app.get("/version")
async def get_version():
    logger.info("📋 Version endpoint accessed")
    return {
        "version": "2.1",
        "deployment_time": datetime.datetime.now().isoformat(),
        "auto_deployment": "enabled",
        "last_update": "CI/CD workflow test - updated response messages",
        "test_status": "✅ GitHub Actions workflow validation",
        "logging": {
            "enabled": True,
            "location": f"{log_dir}/agent.log"
        }
    }

@app.get("/health")
async def health_check():
    logger.info("🏥 Health check performed")
    return {
        "status": "healthy",
        "timestamp": datetime.datetime.now().isoformat(),
        "service": "flight-agent",
        "version": "2.1",
        "test_deployment": "✅ CI/CD workflow validation"
    }

@app.get("/logs/status")
async def logs_status():
    """Check logging status and recent log entries"""
    logger.info("📊 Log status endpoint accessed")
    
    log_file_path = f"{log_dir}/agent.log"
    
    try:
        # Check if log file exists and get its size
        if os.path.exists(log_file_path):
            file_size = os.path.getsize(log_file_path)
            
            # Get last few lines of the log file
            with open(log_file_path, 'r') as f:
                lines = f.readlines()
                recent_logs = lines[-5:] if len(lines) >= 5 else lines
            
            return {
                "status": "active",
                "log_file": log_file_path,
                "file_size_bytes": file_size,
                "recent_entries": [line.strip() for line in recent_logs],
                "timestamp": datetime.datetime.now().isoformat()
            }
        else:
            return {
                "status": "log_file_not_found",
                "log_file": log_file_path,
                "message": "Log file will be created on first log entry",
                "timestamp": datetime.datetime.now().isoformat()
            }
    except Exception as e:
        logger.error(f"❌ Error checking log status: {str(e)}")
        return {
            "status": "error",
            "error": str(e),
            "timestamp": datetime.datetime.now().isoformat()
        }

@app.post("/recommendation")
def recommend(query: Query):
    logger.info(f"🤖 Recommendation request received: {query.input_text[:50]}...")
    
    try:
        result = run_agent(query.input_text)
        logger.info("✅ Recommendation generated successfully")
        return {"response": result}
    except Exception as e:
        logger.error(f"❌ Error generating recommendation: {str(e)}")
        raise

if __name__ == "__main__":
    import uvicorn
    logger.info("🚀 Starting Flight Agent API server...")
    uvicorn.run(app, host="0.0.0.0", port=8000)
